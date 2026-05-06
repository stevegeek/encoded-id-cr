require "spec"
require "../src/encoded_id_cr"

# Fixtures lifted verbatim from the Ruby gem's hex_representation_test.rb
# (group_size = 4) so we get byte-for-byte verification.
HEX = EncodedId::HexRepresentation.new(4)

describe EncodedId::HexRepresentation do
  describe "construction" do
    it "rejects invalid group sizes" do
      expect_raises(EncodedId::InvalidConfigurationError) { EncodedId::HexRepresentation.new(0) }
      expect_raises(EncodedId::InvalidConfigurationError) { EncodedId::HexRepresentation.new(33) }
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
  end

  describe "#integers_as_hex" do
    it "round-trips the boundary fixture" do
      HEX.integers_as_hex([0_i64, 1_i64, 1_i64]).should eq ["100010000"]
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
