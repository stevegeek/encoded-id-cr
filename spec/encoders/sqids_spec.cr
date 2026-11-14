require "../spec_helper"

# Modified Crockford alphabet — same as `EncodedId::Alphabet.modified_crockford`
# in the Ruby gem. The Ruby tests construct one of these and pass it through;
# we use the raw characters here to exercise the encoder's String-form API
# directly (the `Alphabet` wrapper is exercised by alphabet_spec.cr).
MODIFIED_CROCKFORD = "0123456789abcdefghjkmnpqrstuvwxyz"

describe EncodedId::Encoders::Sqids do
  describe "#encode (byte-for-byte fixtures)" do
    it "encodes a single integer to '37vq3u7t'" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.encode([123_i64]).should eq("37vq3u7t")
    end

    it "encodes [123, 456, 789] to 'qa1u2mqvb'" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.encode([123_i64, 456_i64, 789_i64]).should eq("qa1u2mqvb")
    end

    it "does not change later encodings after encoding an id whose offset is 0" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.encode([10_i64]).should eq("gq2nkv4s")
      encoder.encode([123_i64]).should eq("37vq3u7t")
      encoder.decode("gq2nkv4s").should eq([10_i64])
    end

    it "returns empty string for empty input" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.encode([] of Int64).should eq("")
    end

    it "raises InvalidInputError for negative input (review §9)" do
      # Phase 2 MED §9: unified on raise across both encoders + ReversibleId,
      # matching the Ruby parent gem. Previously returned "".
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      expect_raises(EncodedId::InvalidInputError, /negative/) do
        encoder.encode([-1_i64])
      end
    end
  end

  describe "#decode" do
    it "round-trips a single id" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      coded = encoder.encode([123_i64])
      encoder.decode(coded).should eq([123_i64])
    end

    it "round-trips multiple ids" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      ids = [123_i64, 456_i64, 789_i64]
      encoder.decode(encoder.encode(ids)).should eq(ids)
    end

    it "returns empty array for invalid characters" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.decode("$%&*").should eq([] of Int64)
    end

    it "returns empty array for empty input" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.decode("").should eq([] of Int64)
    end

    it "round-trips with a custom alphabet" do
      encoder = EncodedId::Encoders::Sqids.new(8, "0123456789abcdef")
      id = 123_i64
      coded = encoder.encode([id])
      coded.should_not be_empty
      encoder.decode(coded).should eq([id])
    end

    it "returns [] of Int64 for an attacker-supplied long string that overflows Int64" do
      # Regression for CRIT §1: a 30-byte alphabet-only input would otherwise
      # overflow `Int64` inside `to_number` and escape as a 500. Sqids' public
      # contract is "garbage → empty array"; that now extends to the overflow
      # case.
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.decode("a" + "0" * 29).should eq([] of Int64)
    end

    it "returns [] of Int64 (not garbage integers) for a long overflowing alphabet-only input" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      result = encoder.decode("z" * 80)
      result.should eq([] of Int64)
      result.empty?.should be_true
    end

    it "returns [] of Int64 when decoding a string that is not a canonical encoding" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.decode("42").should eq([] of Int64)
      encoder.decode("37vq3u7tx").should eq([] of Int64)
    end

    it "only decodes strings that round-trip" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      chars = MODIFIED_CROCKFORD.chars
      chars.each do |a|
        chars.each do |b|
          candidate = "#{a}#{b}"
          decoded = encoder.decode(candidate)
          next if decoded.empty?
          encoder.encode(decoded).should eq(candidate)
        end
      end
    end

    it "rejects the blocked encoding and accepts the reissued one" do
      unblocked = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD).encode([123_i64])
      blocklist = EncodedId::Blocklist.new([unblocked[0, 4]])
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD, blocklist)
      reissued = encoder.encode([123_i64])

      reissued.should_not eq(unblocked)
      encoder.decode(reissued).should eq([123_i64])
      encoder.decode(unblocked).should eq([] of Int64)
    end

    it "returns [] of Int64 when decoding a string whose value is out of range" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.decode("zzzzzzzzzzzzzzzzzz").should eq([] of Int64)
    end
  end

  describe "validation" do
    it "raises InvalidInputError when alphabet contains multibyte characters" do
      expect_raises(EncodedId::InvalidInputError, /Alphabet cannot contain multibyte characters/) do
        EncodedId::Encoders::Sqids.new(8, "abcdefghijklmnop\u{1F600}\u{1F601}")
      end
    end

    it "raises InvalidInputError for min_length above 255" do
      expect_raises(EncodedId::InvalidInputError, /Minimum length has to be between 0 and 255/) do
        EncodedId::Encoders::Sqids.new(300, MODIFIED_CROCKFORD)
      end
    end

    it "raises InvalidInputError for negative min_length" do
      expect_raises(EncodedId::InvalidInputError, /Minimum length has to be between 0 and 255/) do
        EncodedId::Encoders::Sqids.new(-1, MODIFIED_CROCKFORD)
      end
    end

    it "raises InvalidConfigurationError when the alphabet contains duplicate characters" do
      # Regression for HIGH §3: a duplicate-char alphabet silently broke
      # encode/decode round-trips (decode walks via `Array#index`, which
      # always picks the first slot). Reject up front.
      expect_raises(EncodedId::InvalidConfigurationError, /unique characters/) do
        EncodedId::Encoders::Sqids.new(8, "abcdefghij00")
      end
    end

    it "raises InvalidAlphabetError when the alphabet is shorter than 3 characters" do
      expect_raises(EncodedId::InvalidAlphabetError, "Sqids requires an alphabet of at least 3 unique characters.") do
        EncodedId::Encoders::Sqids.new(8, "ab")
      end
    end

    it "still raises an InvalidConfigurationError for a too-short alphabet" do
      expect_raises(EncodedId::InvalidConfigurationError) do
        EncodedId::Encoders::Sqids.new(8, "ab")
      end
    end

    it "accepts a 3-character alphabet (the canonical Sqids minimum)" do
      # Boundary case: exactly the minimum should succeed.
      encoder = EncodedId::Encoders::Sqids.new(8, "abc")
      encoder.should_not be_nil
    end
  end
end
