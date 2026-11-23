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

    it "encodes integer strings and integral floats as the integer" do
      id = EncodedId::ReversibleId.sqids
      id.encode(["123"]).should eq id.encode(123)
      id.encode(["1", "2"]).should eq id.encode([1, 2])
      id.encode([" 12 "]).should eq id.encode(12)
      id.encode(["1_0"]).should eq id.encode(10)
      id.encode([2.0]).should eq id.encode(2)
    end

    it "raises InvalidInputError for strings and floats that are not integers" do
      id = EncodedId::ReversibleId.sqids
      ["", "abc", "12abc", "1.5", "0x1A"].each do |value|
        expect_raises(EncodedId::InvalidInputError, /must be integers/) { id.encode([value]) }
      end
      [1.9, Float64::NAN, Float64::INFINITY].each do |value|
        expect_raises(EncodedId::InvalidInputError, /must be integers/) { id.encode([value]) }
      end
      expect_raises(EncodedId::InvalidInputError) { id.encode([1e20]) }
    end

    it "encodes 4611686018427387903 and raises above it" do
      id = EncodedId::ReversibleId.sqids
      id.decode(id.encode(4611686018427387903)).should eq [4611686018427387903_i64]
      expect_raises(EncodedId::InvalidInputError, /4611686018427387903/) do
        id.encode(4611686018427387904)
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

    it "decodes with case sensitivity" do
      alphabet = EncodedId::Alphabet.new(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "a", "b", "c", "d", "e"])
      id = EncodedId::ReversibleId.sqids(alphabet: alphabet)
      id.encode(101).should eq "c7a1-271b"
      id.decode("c7a1-271b", downcase: false).should eq [101_i64]
      id.decode("c7A1-271b", downcase: true).should eq [101_i64]
      id.decode("c7A1-271b", downcase: false).should_not eq [101_i64]

      id.encode(123).should eq "4ecb-5dAe"
      id.decode("4ecb-5dAe", downcase: false).should eq [123_i64]
      id.decode("4ecb-5dAe", downcase: true).should eq [] of Int64
    end

    it "returns [] of Int64 when decoding a string it did not issue" do
      id = EncodedId::ReversibleId.sqids
      id.encode(42).should eq "0g69-n738"
      id.decode("42").should eq [] of Int64
    end

    it "decodes its own encoding after normalisation" do
      id = EncodedId::ReversibleId.sqids
      encoded = id.encode(42)
      id.decode(encoded.delete('-')).should eq [42_i64]
      id.decode(encoded.upcase, downcase: true).should eq [42_i64]
      id.decode(encoded.tr("0", "o")).should eq [42_i64]
    end

    it "uses no blocklist by default, like the Ruby gem" do
      id = EncodedId::ReversibleId.sqids
      id.encode(58849).should eq "gtwa-t2nk"
      id.decode("gtwa-t2nk").should eq [58849_i64]
      id.encode(74700).should eq "ycra-pd6m"
      id.decode("ycra-pd6m").should eq [74700_i64]
    end

    it "checks the blocklist only for ids up to blocklist_max_length characters by default" do
      short_only = EncodedId::ReversibleId.sqids(blocklist: ["twat"], blocklist_max_length: 7)
      short_only.encode(58849).should eq "gtwa-t2nk"
      short_only.decode("gtwa-t2nk").should eq [58849_i64]

      checked = EncodedId::ReversibleId.sqids(blocklist: ["twat"], blocklist_max_length: 8)
      reissued = checked.encode(58849)
      reissued.should_not eq "gtwa-t2nk"
      checked.decode(reissued).should eq [58849_i64]
      checked.decode("gtwa-t2nk").should eq [] of Int64
    end

    it "checks the blocklist for ids of any length with blocklist_mode Always" do
      id = EncodedId::ReversibleId.sqids(
        blocklist: ["twat"],
        blocklist_mode: EncodedId::Encoders::BlocklistMode::Always,
        blocklist_max_length: 7,
      )
      id.encode(58849).should_not eq "gtwa-t2nk"
      id.decode("gtwa-t2nk").should eq [] of Int64
    end

    it "returns empty when decoding a string whose value is out of range" do
      id = EncodedId::ReversibleId.sqids
      id.decode("zzzzzzzzzzzzzzzzzz").should eq [] of Int64
      id.decode_hex("zzzzzzzzzzzzzzzzzz").should eq [] of String
    end

    it "raises InvalidAlphabetError with an alphabet of two characters" do
      expect_raises(EncodedId::InvalidAlphabetError, /at least 3 unique characters/) do
        EncodedId::ReversibleId.sqids(alphabet: EncodedId::Alphabet.new("ab"))
      end
    end

    it "accepts an alphabet of three characters" do
      id = EncodedId::ReversibleId.sqids(alphabet: EncodedId::Alphabet.new("abc"), split_at: nil)
      id.decode(id.encode([1, 2, 123456])).should eq [1_i64, 2_i64, 123456_i64]
    end

    it "encodes and decodes with a small alphabet" do
      id = EncodedId::ReversibleId.sqids(alphabet: EncodedId::Alphabet.new("abcdefghij"))
      id.decode(id.encode([1, 2, 123456])).should eq [1_i64, 2_i64, 123456_i64]
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

    it "returns [] of Int64 when decoding characters not in the alphabet" do
      id = EncodedId::ReversibleId.hashid(salt: "test")
      ["!!!!", "é", "éé", id.encode(123) + "!", "\xff", "ab\xffcd", id.encode(123) + "\xff"].each do |coded|
        id.decode(coded).should eq([] of Int64)
        id.decode_hex(coded).should eq([] of String)
      end
    end

    it "raises InvalidAlphabetError with an alphabet of fifteen characters" do
      expect_raises(EncodedId::InvalidAlphabetError, "Hashids requires an alphabet of at least 16 unique characters.") do
        EncodedId::ReversibleId.hashid(salt: "this is my salt", alphabet: EncodedId::Alphabet.new("0123456789abcde"))
      end
    end

    it "accepts an alphabet of sixteen characters" do
      id = EncodedId::ReversibleId.hashid(salt: "this is my salt", alphabet: EncodedId::Alphabet.new("0123456789abcdef"))
      id.decode(id.encode([1, 2, 123456])).should eq [1_i64, 2_i64, 123456_i64]
    end
  end
end
