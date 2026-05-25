require "spec"
require "../src/encoded_id_cr"

describe EncodedId::ReversibleId do
  describe ".sqids" do
    it "round-trips a single id with default settings" do
      id = EncodedId::ReversibleId.sqids
      encoded = id.encode(123)
      encoded.should_not be_empty
      id.decode(encoded).should eq [123_i64]
    end

    it "round-trips multiple ids" do
      id = EncodedId::ReversibleId.sqids
      encoded = id.encode([123_i64, 456_i64, 789_i64])
      id.decode(encoded).should eq [123_i64, 456_i64, 789_i64]
    end

    it "humanizes with the default split_at=4 split_with=- by inserting a separator every 4 chars" do
      id = EncodedId::ReversibleId.sqids
      encoded = id.encode(123)
      # Default min_length is 8, so the raw output is at least 8 chars,
      # which after humanization gets one separator inserted.
      encoded.should match /\A[0-9a-z]{4}-[0-9a-z]{4,}\z/
    end

    it "is byte-compatible with the Ruby gem for the canonical fixture" do
      # From sqids_test.rb: Sqids.new(8, modified_crockford).encode([123]) == "37vq3u7t"
      # Humanized at 4 chars with "-" separator that becomes "37vq-3u7t".
      id = EncodedId::ReversibleId.sqids
      id.encode(123).should eq "37vq-3u7t"
      id.decode("37vq-3u7t").should eq [123_i64]
    end

    it "decodes ids whose case got mangled by URL handling when downcase: true" do
      id = EncodedId::ReversibleId.sqids
      encoded = id.encode(42)
      uppercased = encoded.upcase
      id.decode(uppercased, downcase: true).should eq [42_i64]
    end

    it "applies alphabet equivalences during decode (e.g. 'O' -> '0')" do
      # modified_crockford has 'o' => '0' and 'l' => '1' equivalences. After
      # downcasing, an 'O' in the input gets translated to '0' before decode.
      id = EncodedId::ReversibleId.sqids
      encoded = id.encode(123) # "37vq-3u7t" -- no o/i/l characters here, but
      # we substitute one to prove the mapping kicks in.
      tweaked = encoded.gsub('0', 'O')
      id.decode(tweaked, downcase: true).should eq [123_i64]
    end

    it "allows disabling humanization with split_at: nil" do
      id = EncodedId::ReversibleId.sqids(split_at: nil)
      encoded = id.encode(123)
      encoded.should_not contain "-"
      id.decode(encoded).should eq [123_i64]
    end

    it "rejects negative ids" do
      id = EncodedId::ReversibleId.sqids
      expect_raises(EncodedId::InvalidInputError, /can only be positive/) do
        id.encode([-1_i64])
      end
    end

    it "rejects empty input" do
      id = EncodedId::ReversibleId.sqids
      expect_raises(EncodedId::InvalidInputError, /empty array/) do
        id.encode([] of Int64)
      end
    end

    it "rejects more inputs than max_inputs_per_id" do
      id = EncodedId::ReversibleId.sqids(max_inputs_per_id: 3)
      expect_raises(EncodedId::InvalidInputError, /maximum amount of IDs is 3/) do
        id.encode([1_i64, 2_i64, 3_i64, 4_i64])
      end
    end

    it "raises EncodedIdLengthError when max_length is exceeded" do
      # Force a long output by demanding a min_length that exceeds the cap.
      id = EncodedId::ReversibleId.sqids(min_length: 50, max_length: 10)
      expect_raises(EncodedId::EncodedIdLengthError) do
        id.encode(1)
      end
    end

    it "raises EncodedIdFormatError when decoding an over-length string" do
      id = EncodedId::ReversibleId.sqids(max_length: 5)
      expect_raises(EncodedId::EncodedIdFormatError, /Max length/) do
        id.decode("aaaaaaaa")
      end
    end
  end

  describe ".hashid" do
    it "round-trips a single id" do
      id = EncodedId::ReversibleId.hashid(salt: "this is my salt")
      encoded = id.encode(12345)
      encoded.should_not be_empty
      id.decode(encoded).should eq [12345_i64]
    end

    it "round-trips multiple ids" do
      id = EncodedId::ReversibleId.hashid(salt: "this is my salt")
      encoded = id.encode([1_i64, 2_i64, 3_i64])
      id.decode(encoded).should eq [1_i64, 2_i64, 3_i64]
    end

    it "humanizes the output by default (separator every 4 chars)" do
      id = EncodedId::ReversibleId.hashid(salt: "this is my salt")
      encoded = id.encode(12345)
      encoded.should contain("-")
      id.decode(encoded).should eq [12345_i64]
    end

    it "decodes when separators were stripped or case was mangled" do
      id = EncodedId::ReversibleId.hashid(salt: "this is my salt")
      encoded = id.encode(987)
      id.decode(encoded.gsub("-", "")).should eq [987_i64]
      id.decode(encoded.upcase, downcase: true).should eq [987_i64]
    end

    it "produces different encodings under different salts (round-trips per salt)" do
      a = EncodedId::ReversibleId.hashid(salt: "salt-a")
      b = EncodedId::ReversibleId.hashid(salt: "salt-b")
      a.encode(42).should_not eq b.encode(42)
      a.decode(a.encode(42)).should eq [42_i64]
      b.decode(b.encode(42)).should eq [42_i64]
    end

    it "returns [] of Int64 for an attacker-supplied long string (does NOT raise)" do
      # Regression for CRIT §1 at the public facade: a 30-byte alphabet-only
      # input would previously surface as a 500 (OverflowError) because the
      # encoder's `unhash` overflowed `Int64`. The contract is now "garbage →
      # empty array" all the way through the facade.
      id = EncodedId::ReversibleId.hashid(salt: "test")
      id.decode("a" * 30).should eq([] of Int64)
    end
  end
end
