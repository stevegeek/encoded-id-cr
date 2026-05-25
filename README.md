# encoded_id_cr

A Crystal port of the [`encoded_id`](https://github.com/stevegeek/encoded_id) Ruby gem. Encode integer IDs (or hex strings like UUIDs) into short, obfuscated, reversible strings suitable for URLs.

The internal Sqids and Hashids encoders are **byte-for-byte compatible** with the Ruby gem's optimised implementations — IDs encoded by the Ruby version round-trip cleanly through this port and vice versa.

## What's ported

| Component | Status |
|---|---|
| `Alphabet` (with confusable-character equivalences) | ✓ |
| `CharHelpers` (humanize / unhumanize) | ✓ |
| `HexRepresentation` (hex strings ↔ integer arrays) | ✓ |
| Sqids encoder (the gem's optimised `MySqids`) | ✓ |
| Hashids encoder (the gem's optimised `Hashid`) | ✓ |
| `ReversibleId` facade with `.sqids` / `.hashid` factories | ✓ |
| `cr_encoded_id` CLI | ✓ |
| Hashids blocklist enforcement | ✓ (raises `BlocklistError` on collision) |
| Configuration objects (`HashidConfiguration`, etc.) | replaced by direct kwargs |
| Rails integration (`encoded_id-rails`) | out of scope |

## Library usage

```crystal
require "encoded_id_cr"

# Sqids (default — no salt required)
id = EncodedId::ReversibleId.sqids
id.encode(123)                          # => "37vq-3u7t"
id.decode("37vq-3u7t")                  # => [123_i64]
id.encode([123_i64, 456_i64, 789_i64])  # => humanised "qa1u-2mqv-b…"

# Hashids (salt required)
hid = EncodedId::ReversibleId.hashid(salt: "this is my salt")
hid.encode(12345)                       # => "9da2-a7an"
hid.decode("9da2-a7an")                 # => [12345_i64]

# Hex (UUIDs etc.)
id.encode_hex("550e8400e29b41d4a716446655440000")
id.decode_hex(encoded)                  # => ["550e8400e29b41d4a716446655440000"]

# Tolerant decoding (case-insensitive, separator-agnostic)
id.decode("37VQ3U7T", downcase: true)   # => [123_i64]
id.decode("37vq3u7t")                   # => [123_i64]

# Customise
EncodedId::ReversibleId.sqids(
  alphabet: EncodedId::Alphabet.alphanum,
  min_length: 12,
  split_at: 6,
  split_with: "_",
  max_inputs_per_id: 16,
  max_length: 64,
)
```

## CLI

A `cr_encoded_id` binary is built via `shards build`:

```bash
CRYSTAL_LIBRARY_PATH=$HOME/.asdf/installs/crystal/1.20.1/embedded/lib shards build cr_encoded_id
# => bin/cr_encoded_id
```

(The `CRYSTAL_LIBRARY_PATH` prefix is needed because asdf 0.18 doesn't propagate the embedded libgc path. See `script/cr` for the same workaround applied to one-off `crystal` calls.)

Then:

| Command | Output |
|---|---|
| `bin/cr_encoded_id encode 12345` | sqids → `a9h3-yxzg` |
| `bin/cr_encoded_id encode 12345 --salt foo` | hashid → `9da2-a7an` |
| `bin/cr_encoded_id encode 1 2 3 --salt foo` | multi-id hashid → `dm2s-9cxn` |
| `bin/cr_encoded_id decode 9da2-a7an --salt foo` | → `12345` |
| `bin/cr_encoded_id encode 12345 --salt foo --no-humanize` | no `-` separator → `9da2a7an` |
| `bin/cr_encoded_id encode 12345 --alphabet alphanum` | full alphanumeric alphabet |
| `bin/cr_encoded_id encode_hex 1A2B --salt foo` | encode a hex string (UUIDs etc.) |
| `bin/cr_encoded_id decode_hex <encoded> --salt foo` | decode → original hex string(s) |
| `bin/cr_encoded_id --help` | full options list |

The encoder is chosen based on whether you pass `--salt`: with a salt it's Hashids, without it's Sqids. Override with `--encoder=sqids` or `--encoder=hashid`.

## Development

```bash
script/cr spec      # 106 specs, all green
script/cr build src/encoded_id_cr.cr -o /tmp/check    # type-check the library
shards build cr_encoded_id   # rebuild the CLI
```

`script/cr` is a thin wrapper around `crystal` that exports `CRYSTAL_LIBRARY_PATH` for asdf 0.18 compatibility.

## Compatibility note

The Sqids/Hashids byte-compatibility is verified against published fixtures from the Ruby gem's test suite — e.g. `Hashid.new(salt, 0).encode([12345]) == "NkK9"`, `Sqids.new(8, modified_crockford).encode([123]) == "37vq3u7t"`. See `spec/encoders/*_spec.cr` for the full list.
