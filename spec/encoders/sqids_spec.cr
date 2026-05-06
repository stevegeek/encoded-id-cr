require "spec"

# Don't load the project entry point (src/encoded_id_cr.cr) — it requires
# alphabet/char_helpers files owned by a sibling agent that may not yet exist
# in this worktree. We define the EncodedId error classes locally and require
# only the encoder.
module EncodedId
  class Error < Exception; end

  class InvalidAlphabetError < Error; end

  class InvalidConfigurationError < Error; end

  class InvalidInputError < Error; end

  class EncodedIdFormatError < Error; end

  class EncodedIdLengthError < Error; end
end

require "../../src/encoded_id_cr/encoders/sqids"

# Modified Crockford alphabet — same as ::EncodedId::Alphabet.modified_crockford
# in the Ruby gem. The Ruby tests construct one of these and pass it through;
# we accept the bare characters because the Alphabet wrapper is owned by
# another agent.
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

    it "returns empty string for empty input" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.encode([] of Int64).should eq("")
    end

    it "returns empty string for negative input" do
      encoder = EncodedId::Encoders::Sqids.new(8, MODIFIED_CROCKFORD)
      encoder.encode([-1_i64]).should eq("")
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
  end
end
