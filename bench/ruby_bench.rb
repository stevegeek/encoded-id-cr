# Ruby-side benchmark mirroring bench/crystal_bench.cr.
# Runs against the user's encoded_id gem at ~/work/containers/ruby_gems/encoded_id
# without modifying it. Loads only the optimised internal encoders so this
# compares the same algorithm we ported into Crystal (MySqids, Hashid).
#
# Usage:
#   ruby bench/ruby_bench.rb
#
# Requires `benchmark/ips` (`gem install benchmark-ips` once if missing).

require "benchmark/ips"
require "rbconfig"

GEM_LIB = ENV["ENCODED_ID_LIB"] || File.expand_path("~/work/containers/ruby_gems/encoded_id/lib")
$LOAD_PATH.unshift(GEM_LIB)

require "encoded_id/alphabet"
require "encoded_id/encoders/hashid_salt"
require "encoded_id/encoders/hashid_consistent_shuffle"
require "encoded_id/encoders/hashid_ordinal_alphabet_separator_guards"
require "encoded_id/encoders/hashid"
require "encoded_id/encoders/my_sqids"  # top-level class MySqids — the optimised internal Sqids

ALPHA       = EncodedId::Alphabet.modified_crockford
SALT_STR    = "this is my salt"
SALT        = EncodedId::Encoders::HashidSalt.new(SALT_STR)
SQIDS_OP    = MySqids.new(min_length: 8, alphabet: ALPHA.characters, blocklist: [])
HASHID_OP   = EncodedId::Encoders::Hashid.new(SALT, 0, ALPHA)

SINGLE_ID   = [12345]
FIVE_IDS    = [1, 2, 3, 4, 5]
SQIDS_ENC1  = SQIDS_OP.encode(SINGLE_ID)
SQIDS_ENC5  = SQIDS_OP.encode(FIVE_IDS)
HASHID_ENC1 = HASHID_OP.encode(SINGLE_ID)
HASHID_ENC5 = HASHID_OP.encode(FIVE_IDS)

puts "Ruby encoded_id benchmark"
puts "ruby #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts

Benchmark.ips do |x|
  x.report("sqids encode 1 id   ") { SQIDS_OP.encode(SINGLE_ID) }
  x.report("sqids encode 5 ids  ") { SQIDS_OP.encode(FIVE_IDS) }
  x.report("sqids decode 1 id   ") { SQIDS_OP.decode(SQIDS_ENC1) }
  x.report("sqids decode 5 ids  ") { SQIDS_OP.decode(SQIDS_ENC5) }
  x.report("hashid encode 1 id  ") { HASHID_OP.encode(SINGLE_ID) }
  x.report("hashid encode 5 ids ") { HASHID_OP.encode(FIVE_IDS) }
  x.report("hashid decode 1 id  ") { HASHID_OP.decode(HASHID_ENC1) }
  x.report("hashid decode 5 ids ") { HASHID_OP.decode(HASHID_ENC5) }
end
