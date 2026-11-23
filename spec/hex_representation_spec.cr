require "spec"
require "../src/encoded_id_cr"

# Fixtures lifted verbatim from the Ruby gem's hex_representation_test.rb
# (group_size = 4) so we get byte-for-byte verification.
HEX = EncodedId::HexRepresentation.new(4)

describe EncodedId::HexRepresentation do
  describe "construction" do
    it "rejects invalid group sizes" do
      expect_raises(EncodedId::InvalidConfigurationError) { EncodedId::HexRepresentation.new(0) }
      expect_raises(EncodedId::InvalidConfigurationError, "hex_digit_encoding_group_size must be an integer in 1..12") do
        EncodedId::HexRepresentation.new(13)
      end
    end

    it "accepts the largest group size" do
      hex = EncodedId::HexRepresentation.new(12)
      hex.hex_as_integers(["ffffffffffff", "0"]).should eq [16_i64**12 - 1, 16_i64**12, 0_i64]
    end
  end

  describe "#hex_as_integers" do
    it "single byte hex value" do
      HEX.hex_as_integers("c0").should eq [192_i64]
    end

    it "max group value" do
      HEX.hex_as_integers("ffff").should eq [65535_i64]
    end

    it "splits at boundary" do
      HEX.hex_as_integers("10000").should eq [0_i64, 1_i64]
    end

    it "splits at next boundary" do
      HEX.hex_as_integers("100010000").should eq [0_i64, 1_i64, 1_i64]
    end

    it "adds a length marker for leading zeros" do
      HEX.hex_as_integers("00ff").should eq [255_i64, 65541_i64]
      HEX.hex_as_integers("000").should eq [0_i64, 65540_i64]
    end

    it "adds no length marker without leading zeros" do
      HEX.hex_as_integers("ff").should eq [255_i64]
      HEX.hex_as_integers("10000").should eq [0_i64, 1_i64]
      HEX.hex_as_integers("0").should eq [0_i64]
    end

    it "raises for a string with no hex digits" do
      expect_raises(EncodedId::InvalidInputError, %(Hex string "zz" contains no hex digits)) do
        HEX.hex_as_integers("zz")
      end
      expect_raises(EncodedId::InvalidInputError) { HEX.hex_as_integers(["ab", "--"]) }
    end
  end

  describe "#integers_as_hex" do
    it "round-trips the boundary fixture" do
      HEX.integers_as_hex([0_i64, 1_i64, 1_i64]).should eq ["100010000"]
    end

    it "keeps leading zeros and empty strings recorded by length markers" do
      HEX.integers_as_hex([255_i64, 65541_i64]).should eq ["00ff"]
      HEX.integers_as_hex([0_i64, 65540_i64]).should eq ["000"]
      HEX.integers_as_hex([65537_i64]).should eq [""]
      HEX.integers_as_hex([65537_i64, 65536_i64, 171_i64]).should eq ["", "ab"]
      HEX.integers_as_hex([171_i64, 65536_i64, 18_i64, 65541_i64]).should eq ["ab", "0012"]
      HEX.integers_as_hex([0_i64, 65541_i64, 65536_i64, 0_i64, 0_i64]).should eq ["0000", "00000"]
    end

    it "keeps an empty later element" do
      HEX.integers_as_hex([171_i64, 65536_i64, 65536_i64, 205_i64]).should eq ["ab", "", "cd"]
      HEX.integers_as_hex([171_i64, 65536_i64]).should eq ["ab", ""]
    end

    it "drops an empty first element that has no length marker" do
      HEX.integers_as_hex([65536_i64, 171_i64]).should eq ["ab"]
    end

    it "returns [] for integer layouts that encoding never produces" do
      [
        [65542_i64],
        [1_i64, 65542_i64],
        [1_i64, 65541_i64, 2_i64],
        [65537_i64, 65537_i64],
        [5_i64, 65537_i64],
        [65539_i64],
        [171_i64, 65536_i64, 65539_i64],
        [511_i64, 65539_i64],
        [171_i64, 65539_i64],
        [2748_i64, 65540_i64],
      ].each do |integers|
        HEX.integers_as_hex(integers).should eq([] of String)
      end
    end

    it "round-trips a typical UUID-shape value" do
      uuid_hex = "550e8400e29b41d4a716446655440000"
      ints = HEX.hex_as_integers(uuid_hex)
      HEX.integers_as_hex(ints).should eq [uuid_hex]
    end

    it "round-trips multiple hex strings via the sentinel separator" do
      hexes = ["deadbeef", "cafebabe", "1234"]
      ints = HEX.hex_as_integers(hexes)
      HEX.integers_as_hex(ints).should eq hexes
    end

    it "filters non-hex characters before encoding" do
      HEX.hex_as_integers("c0-ff:ee").should eq HEX.hex_as_integers("c0ffee")
    end

    it "rejects empty hex entries instead of silently dropping them (review §6)" do
      # Regression for MED §6: previously `hex_as_integers(["", "abc"])`
      # silently dropped the leading empty entry. Silent data loss is worse
      # than a loud error.
      expect_raises(ArgumentError, /Empty hex string/) do
        HEX.hex_as_integers(["", "abc"])
      end
      expect_raises(ArgumentError, /Empty hex string/) do
        HEX.hex_as_integers(["abc", ""])
      end
    end
  end
end

TAGGED_HEX = EncodedId::TaggedHexRepresentation.new

describe EncodedId::TaggedHexRepresentation do
  describe "#hex_as_integers" do
    it "makes a short hex string one last chunk" do
      TAGGED_HEX.hex_as_integers("c0").should eq [0x2c0_i64]
    end

    it "keeps leading zeros in the chunk" do
      TAGGED_HEX.hex_as_integers("00ff").should eq [0x200ff_i64]
    end

    it "splits a UUID into balanced chunks" do
      TAGGED_HEX.hex_as_integers("9a566b8b-8618-42ab-8db7-a5a0276401fd").should eq [
        0x19a566b8b861_i64, 0x1842ab8db7a5_i64, 0x2a0276401fd_i64,
      ]
    end

    it "splits at the chunk boundaries" do
      TAGGED_HEX.hex_as_integers("0" * 15).should eq [0x2000000000000000_i64]
      TAGGED_HEX.hex_as_integers("0" * 16).should eq [0x100000000_i64, 0x200000000_i64]
      TAGGED_HEX.hex_as_integers("0" * 30).should eq [0x1000000000000000_i64, 0x2000000000000000_i64]
      TAGGED_HEX.hex_as_integers("0" * 31).should eq [0x100000000000_i64, 0x10000000000_i64, 0x20000000000_i64]
    end

    it "ends each of multiple strings with a last chunk" do
      TAGGED_HEX.hex_as_integers(["ab", "0", "cd"]).should eq [0x2ab_i64, 0x20_i64, 0x2cd_i64]
    end

    it "encodes upper case input as lower case" do
      TAGGED_HEX.hex_as_integers("ABCDEF").should eq TAGGED_HEX.hex_as_integers("abcdef")
    end

    it "raises for a string with no hex digits" do
      expect_raises(EncodedId::InvalidInputError, %(Hex string "zz" contains no hex digits)) do
        TAGGED_HEX.hex_as_integers(["ab", "zz"])
      end
    end

    it "rejects empty hex entries" do
      expect_raises(ArgumentError, /Empty hex string/) { TAGGED_HEX.hex_as_integers(["ab", ""]) }
    end
  end

  describe "#integers_as_hex" do
    it "round-trips" do
      ["00ff", ["ab", "0012"], "f" * 15, "0" * 31, ["9a566b8b861842ab8db7a5a0276401fd", "0"]].each do |input|
        hexes = input.is_a?(String) ? [input] : input
        TAGGED_HEX.integers_as_hex(TAGGED_HEX.hex_as_integers(hexes)).should eq hexes
      end
    end

    it "decodes empty strings" do
      TAGGED_HEX.integers_as_hex([0x2_i64, 0x20_i64]).should eq ["", "0"]
      TAGGED_HEX.integers_as_hex([0x2ab_i64, 0x2_i64, 0x20012_i64]).should eq ["ab", "", "0012"]
    end

    it "rejects values without a valid tag" do
      TAGGED_HEX.integers_as_hex([0x3ab_i64]).should eq([] of String)
      TAGGED_HEX.integers_as_hex([0_i64]).should eq([] of String)
      TAGGED_HEX.integers_as_hex([-0x2ab_i64]).should eq([] of String)
    end

    it "rejects a string without a last chunk" do
      TAGGED_HEX.integers_as_hex([0x2ab_i64, 0x1000000000000000_i64]).should eq([] of String)
    end

    it "rejects lists that are not how the strings encode" do
      [
        [0x1ab_i64, 0x2cd_i64],
        [0x1_i64, 0x2ab_i64],
        [0x1000000000000000_i64, 0x2_i64],
        [0x1000000000000000_i64, 0x20_i64],
        [0x10000_i64, 0x200000000000_i64],
        [0x100_i64, 0x2_i64],
        [0x1000000000000000_i64, 0x1000000000000000_i64, 0x20_i64],
        [0x10000000000_i64, 0x100000000000_i64, 0x20000000000_i64],
        [0x100000000000_i64, 0x1000000000_i64, 0x200000000000_i64],
      ].each do |integers|
        TAGGED_HEX.integers_as_hex(integers).should eq([] of String)
      end
    end
  end
end

describe EncodedId::ReversibleId do
  describe "#encode_hex / #decode_hex" do
    it "round-trips a single hex string via Sqids" do
      id = EncodedId::ReversibleId.sqids
      encoded = id.encode_hex("deadbeef")
      id.decode_hex(encoded).should eq ["deadbeef"]
    end

    it "round-trips a UUID via Hashid" do
      id = EncodedId::ReversibleId.hashid(salt: "this is my salt")
      uuid = "550e8400e29b41d4a716446655440000"
      encoded = id.encode_hex(uuid)
      id.decode_hex(encoded).should eq [uuid]
    end

    it "round-trips multiple hex strings" do
      id = EncodedId::ReversibleId.sqids
      hexes = ["deadbeef", "cafebabe", "1234"]
      encoded = id.encode_hex(hexes)
      id.decode_hex(encoded).should eq hexes
    end
  end
end

HEX_SALT = "lha83hk73y9r3jp9js98ugo84"
UUID     = "9a566b8b-8618-42ab-8db7-a5a0276401fd"
LEGACY   = EncodedId::HexEncoding::Legacy
TAGGED   = EncodedId::HexEncoding::Tagged

private def gem_sqids(**options)
  EncodedId::ReversibleId.sqids(**options, blocklist: EncodedId::Blocklist.empty)
end

describe EncodedId::ReversibleId do
  describe "hex encodings" do
    it "defaults to the tagged hex encoding" do
      EncodedId::ReversibleId.sqids.hex_encoding.should eq TAGGED
      EncodedId::ReversibleId.hashid(salt: HEX_SALT).hex_encoding.should eq TAGGED
    end

    it "matches the Ruby gem's legacy Hashid hex fixtures" do
      EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY).encode_hex("f1").should eq "zryg-pey4"
      EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY).encode_hex(["f1", "c2", "1a"]).should eq "x2vh-kjrg-t4qt-nzm3-fn2"
      mixed = ["1", "c0", "97349ffe152d0013", "f0000"]
      EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY).encode_hex(mixed)
        .should eq "bbhb-495h-bzud-269u-pc3k-nfnm-3gsj-9xa0-zg24-trtz"
      EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY, hex_digit_encoding_group_size: 8).encode_hex(mixed)
        .should eq "54ha-289r-a95t-4j0j-4pa2-ja9c-v3m8-z2g1-qxjp-ak8n-08j6-ga8g-kujj-ae6"
      EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY).encode_hex(UUID)
        .should eq "nbbm-c6kj-cz98-2u64-bqcz-9j4h-k4ea-t2km-6ce4-mp"
      EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY).decode_hex("9b7x-kjya").should eq ["ff"]
    end

    it "matches the Ruby gem's tagged Hashid hex fixture" do
      coder = EncodedId::ReversibleId.hashid(salt: HEX_SALT)
      coder.encode_hex(UUID).should eq "9rr6-43ab-jm42-1bnq-bpdv-qr5v-hj6p-9ggx-n3p"
      coder.decode_hex("9rr6-43ab-jm42-1bnq-bpdv-qr5v-hj6p-9ggx-n3p").should eq [UUID.delete('-')]
      coder.decode_hex("zryg-pey4", scheme: LEGACY).should eq ["f1"]
    end

    it "matches the Ruby gem's Sqids hex fixtures" do
      gem_sqids(hex_encoding: LEGACY).encode_hex(UUID).should eq "vex1-w84t-pd6u-zmgq-txjm-bcgg-496x-420a-5wh"
      gem_sqids(hex_encoding: LEGACY).decode_hex("3h3q-3u7t").should eq ["ff"]
      gem_sqids.encode_hex(UUID).should eq "uvzt-2fpj-y7sb-0y4b-r7tj-5ex9-v419-05"
      gem_sqids.decode_hex("k4c3-xs8j").should eq ["", "00ff"]
    end

    it "decodes with the scheme given to decode_hex" do
      gem_sqids.decode_hex("3h3q-3u7t").should eq([] of String)
      gem_sqids.decode_hex("3h3q-3u7t", scheme: LEGACY).should eq ["ff"]
      gem_sqids(hex_encoding: LEGACY).decode_hex("k4c3-xs8j", scheme: TAGGED).should eq ["", "00ff"]
    end

    it "keeps leading zeros in the round trip" do
      inputs = [["00ff"], ["ab", "0012"], ["000"], ["0000", "00000"], ["0a566b8b-8618-42ab-8db7-a5a0276401fd"]]
      [
        EncodedId::ReversibleId.sqids(hex_encoding: LEGACY, max_length: nil),
        EncodedId::ReversibleId.sqids(hex_encoding: LEGACY, hex_digit_encoding_group_size: 8, max_length: nil),
        EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY, max_length: nil),
        EncodedId::ReversibleId.sqids(max_length: nil),
        EncodedId::ReversibleId.hashid(salt: HEX_SALT, max_length: nil),
      ].each do |coder|
        inputs.each do |input|
          coder.decode_hex(coder.encode_hex(input)).should eq input.map(&.delete('-'))
        end
      end
    end

    it "round-trips with a group size of 12" do
      coder = EncodedId::ReversibleId.sqids(hex_encoding: LEGACY, hex_digit_encoding_group_size: 12, max_length: nil)
      hex = ["f" * 36, "00ff"]
      coder.decode_hex(coder.encode_hex(hex)).should eq hex
    end

    it "raises for a group size above 12" do
      expect_raises(EncodedId::InvalidConfigurationError) do
        EncodedId::ReversibleId.sqids(hex_digit_encoding_group_size: 13)
      end
    end

    it "raises InvalidInputError for a hex string with no hex digits" do
      expect_raises(EncodedId::InvalidInputError, %(Hex string "zz" contains no hex digits)) do
        EncodedId::ReversibleId.sqids.encode_hex("zz")
      end
      expect_raises(EncodedId::InvalidInputError) do
        EncodedId::ReversibleId.hashid(salt: HEX_SALT).encode_hex(["ab", "zz", "cd"])
      end
    end

    it "fits three UUIDs in the default max_length" do
      uuids = [UUID, "59f3905a-e704-4714-b42e-960c82b699fe", "9c0498f3-639d-41ed-87c3-715c61e14798"]
      coder = EncodedId::ReversibleId.sqids
      coder.decode_hex(coder.encode_hex(uuids)).should eq uuids.map(&.delete('-'))
    end

    it "raises EncodedIdFormatError when decode_hex input exceeds max_length" do
      coder = EncodedId::ReversibleId.hashid(salt: HEX_SALT, hex_encoding: LEGACY, max_length: nil)
      coded = coder.encode_hex([UUID, "59f3905a-e704-4714-b42e-960c82b699fe", "9c0498f3-639d-41ed-87c3-715c61e14798"])
      expect_raises(EncodedId::EncodedIdFormatError) do
        EncodedId::ReversibleId.hashid(salt: HEX_SALT, max_length: 72).decode_hex(coded)
      end
    end
  end
end
