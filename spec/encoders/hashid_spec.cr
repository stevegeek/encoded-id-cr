require "spec"
require "../../src/encoded_id_cr"

# Fixture pairs are taken verbatim from the Ruby gem's
# test/encoded_id/encoders/hash_id_test.rb so we can verify byte-for-byte
# compatibility with the upstream encoded_id implementation.
SALT          = EncodedId::Encoders::HashidSalt.new("this is my salt")
DEFAULT_SEPS  = "cfhistuCFHISTU".chars.map(&.ord)
DEFAULT_ALPHA = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890".chars.map(&.ord)

# Test-only subclass that exposes the private `unhash` for fixture verification.
# Production code must not call `unhash` directly — use `decode`, which wraps
# `unhash` with `DecodePayloadOverflowError` handling.
class TestableHashid < EncodedId::Encoders::Hashid
  def _unhash_for_spec(input : String, alphabet : Array(Int32)) : Int64
    unhash(input, alphabet)
  end
end

DEFAULT_HASH = TestableHashid.new(SALT)

class ShuffleHarness
  include EncodedId::Encoders::HashidConsistentShuffle
end

describe EncodedId::Encoders::HashidConsistentShuffle do
  it "returns the alphabet unchanged for an empty salt" do
    harness = ShuffleHarness.new
    harness.consistent_shuffle!(DEFAULT_ALPHA.dup, [] of Int32, nil, 0).should eq DEFAULT_ALPHA
  end

  it "shuffles consistently for known fixtures" do
    harness = ShuffleHarness.new
    salt_chars = SALT.salt.chars.map(&.ord)
    harness.consistent_shuffle!("ab".chars.map(&.ord), salt_chars, nil, salt_chars.size)
      .should eq "ba".chars.map(&.ord)
    harness.consistent_shuffle!("abc".chars.map(&.ord), salt_chars, nil, salt_chars.size)
      .should eq "bca".chars.map(&.ord)
    harness.consistent_shuffle!("abcd".chars.map(&.ord), salt_chars, nil, salt_chars.size)
      .should eq "cadb".chars.map(&.ord)
    harness.consistent_shuffle!("abcde".chars.map(&.ord), salt_chars, nil, salt_chars.size)
      .should eq "dceba".chars.map(&.ord)
    harness.consistent_shuffle!(DEFAULT_ALPHA.dup, "salt".chars.map(&.ord), nil, 4)
      .should eq "f17a8zvCwo0iuqYDXlJ4RmAS2end5ghTcpjbOWLK9GFyE6xUI3ZBMQtPsNHrkV".chars.map(&.ord)
  end

  it "uses salt_part_2 when max_salt_length exceeds salt_part_1.size" do
    harness = ShuffleHarness.new
    salt_chars = SALT.salt.chars.map(&.ord)
    harness.consistent_shuffle!(
      "abcdefghijklmnopqrstuvwxyz".chars.map(&.ord),
      salt_chars[0..-3],
      salt_chars[-2..],
      salt_chars.size,
    ).should eq "fcaodykrgqvblxjwmtupzeisnh".chars.map(&.ord)
  end

  it "raises SaltError (not IndexError) when salt_part_2 is too short (review §7)" do
    # Regression for MED §7: only the nil-check on salt_part_2 ran here, so an
    # undersized salt_part_2 used to crash later with `IndexError` from the
    # indexed access inside the loop. Convert that into a useful `SaltError`
    # up front.
    harness = ShuffleHarness.new
    expect_raises(EncodedId::SaltError, /Salt is too short/) do
      harness.consistent_shuffle!(
        "abcdef".chars.map(&.ord),
        [1, 2],       # salt_part_1.size = 2
        [3] of Int32, # salt_part_2.size = 1; need salt_part_2.size >= 8
        10,           # max_salt_length = 10
      )
    end
  end
end

describe EncodedId::Encoders::HashidOrdinalAlphabetSeparatorGuards do
  it "exposes the canonical default separators" do
    EncodedId::Encoders::HashidOrdinalAlphabetSeparatorGuards::DEFAULT_SEPS
      .should eq DEFAULT_SEPS
  end
end

describe EncodedId::Encoders::Hashid do
  describe "construction" do
    it "defaults to a min length of 0" do
      DEFAULT_HASH.min_hash_length.should eq 0
    end

    it "rejects negative min length" do
      expect_raises(ArgumentError, /must be a Integer and greater than or equal to 0/) do
        EncodedId::Encoders::Hashid.new(SALT, -1)
      end
    end

    it "requires the alphabet to have at least 16 unique characters" do
      expect_raises(EncodedId::InvalidAlphabetError) do
        EncodedId::Encoders::Hashid.new(SALT, 0, EncodedId::Alphabet.new("shortalphabet"))
      end
    end

    it "rejects alphabets containing whitespace" do
      expect_raises(EncodedId::InvalidAlphabetError) do
        EncodedId::Encoders::Hashid.new(SALT, 0, EncodedId::Alphabet.new("abc odefghijklmnopqrstuv"))
      end
    end

    it "produces a final alphabet that can be shorter than the input" do
      h = EncodedId::Encoders::Hashid.new(SALT, 0, EncodedId::Alphabet.new("cfhistuCFHISTU01"))
      h.alphabet_ordinals.map(&.unsafe_chr.to_s).should eq ["1", "0"]
    end

    it "rejects multibyte characters in the alphabet (review §8)" do
      # Regression for MED §8: Hashid previously silently accepted multibyte
      # alphabet characters even though Sqids rejected them. Unified on
      # reject.
      multibyte_alphabet = EncodedId::Alphabet.new("abcdefghijklmnop\u{1F600}\u{1F601}")
      expect_raises(EncodedId::InvalidConfigurationError, /multibyte/) do
        EncodedId::Encoders::Hashid.new(SALT, 0, multibyte_alphabet)
      end
    end

    it "rejects multibyte characters in the salt (review §8)" do
      multibyte_salt = EncodedId::Encoders::HashidSalt.new("salt-\u{1F600}")
      expect_raises(EncodedId::InvalidConfigurationError, /multibyte/) do
        EncodedId::Encoders::Hashid.new(multibyte_salt)
      end
    end
  end

  describe "#encode (single number)" do
    it "encodes a single number to the canonical Ruby fixture" do
      DEFAULT_HASH.encode([12345_i64]).should eq "NkK9"
    end

    it "matches the published Ruby fixtures across a range of values" do
      DEFAULT_HASH.encode([1_i64]).should eq "NV"
      DEFAULT_HASH.encode([22_i64]).should eq "K4"
      DEFAULT_HASH.encode([333_i64]).should eq "OqM"
      DEFAULT_HASH.encode([9999_i64]).should eq "kQVg"
      DEFAULT_HASH.encode([123_000_i64]).should eq "58LzD"
      DEFAULT_HASH.encode([456_000_000_i64]).should eq "5gn6mQP"
      DEFAULT_HASH.encode([987_654_321_i64]).should eq "oyjYvry"
    end
  end

  describe "#encode (multiple numbers)" do
    it "matches the published Ruby fixtures" do
      DEFAULT_HASH.encode([1_i64, 2_i64, 3_i64]).should eq "laHquq"
      DEFAULT_HASH.encode([2_i64, 4_i64, 6_i64]).should eq "44uotN"
      DEFAULT_HASH.encode([99_i64, 25_i64]).should eq "97Jun"
      DEFAULT_HASH.encode([1337_i64, 42_i64, 314_i64]).should eq "7xKhrUxm"
      DEFAULT_HASH.encode([683_i64, 94108_i64, 123_i64, 5_i64]).should eq "aBMswoO2UB3Sj"
      DEFAULT_HASH.encode([547_i64, 31_i64, 241271_i64, 311_i64, 31397_i64, 1129_i64, 71129_i64])
        .should eq "3RoSDhelEyhxRsyWpCx5t1ZK"
      DEFAULT_HASH.encode([21979508_i64, 35563591_i64, 57543099_i64, 93106690_i64, 150649789_i64])
        .should eq "p2xkL3CK33JjcrrZ8vsw4YRZueZX9k"
    end

    it "returns empty string for empty input" do
      DEFAULT_HASH.encode([] of Int64).should eq ""
    end

    it "raises InvalidInputError if any number is negative (review §9)" do
      # Phase 2 MED §9: unified on raise across both encoders + ReversibleId,
      # matching the Ruby parent gem. Previously returned "".
      expect_raises(EncodedId::InvalidInputError, /negative/) do
        DEFAULT_HASH.encode([-1_i64])
      end
      expect_raises(EncodedId::InvalidInputError, /negative/) do
        DEFAULT_HASH.encode([10_i64, -10_i64])
      end
    end

    it "does not produce repeating patterns for identical numbers" do
      DEFAULT_HASH.encode([5_i64, 5_i64, 5_i64, 5_i64]).should eq "1Wc8cwcE"
    end

    it "does not produce repeating patterns for incremented numbers" do
      DEFAULT_HASH.encode((1..10).map(&.to_i64).to_a).should eq "kRHnurhptKcjIDTWC3sx"
    end

    it "does not produce similarities between incrementing number hashes" do
      DEFAULT_HASH.encode([1_i64]).should eq "NV"
      DEFAULT_HASH.encode([2_i64]).should eq "6m"
      DEFAULT_HASH.encode([3_i64]).should eq "yD"
      DEFAULT_HASH.encode([4_i64]).should eq "2l"
      DEFAULT_HASH.encode([5_i64]).should eq "rD"
    end
  end

  describe "#encode (with min length)" do
    it "pads to the specified minimum length" do
      h = EncodedId::Encoders::Hashid.new(SALT, 18)
      h.encode([1_i64]).should eq "aJEDngB0NV05ev1WwP"
      h.encode([4140_i64, 21147_i64, 115975_i64, 678570_i64, 4213597_i64, 27644437_i64])
        .should eq "pLMlCWnJSXr1BSpKgqUwbJ7oimr7l6"
    end
  end

  describe "#encode (custom alphabet)" do
    it "round-trips with a custom alphabet" do
      h = EncodedId::Encoders::Hashid.new(SALT, 0, EncodedId::Alphabet.new("ABCDEFGhijklmn34567890-:"))
      h.encode([1_i64, 2_i64, 3_i64, 4_i64, 5_i64]).should eq "6nhmFDikA0"
      h.decode("6nhmFDikA0").should eq [1_i64, 2_i64, 3_i64, 4_i64, 5_i64]
    end
  end

  describe "#decode" do
    it "decodes the canonical fixtures" do
      DEFAULT_HASH.decode("NkK9").should eq [12345_i64]
      DEFAULT_HASH.decode("5O8yp5P").should eq [666555444_i64]
      DEFAULT_HASH.decode("KVO9yy1oO5j").should eq [666555444333222_i64]
      DEFAULT_HASH.decode("Wzo").should eq [1337_i64]
      DEFAULT_HASH.decode("DbE").should eq [808_i64]
      DEFAULT_HASH.decode("yj8").should eq [303_i64]
    end

    it "decodes lists" do
      DEFAULT_HASH.decode("1gRYUwKxBgiVuX").should eq [66655_i64, 5444333_i64, 2_i64, 22_i64]
      DEFAULT_HASH.decode("aBMswoO2UB3Sj").should eq [683_i64, 94108_i64, 123_i64, 5_i64]
      DEFAULT_HASH.decode("jYhp").should eq [3_i64, 4_i64]
      DEFAULT_HASH.decode("k9Ib").should eq [6_i64, 5_i64]
      DEFAULT_HASH.decode("EMhN").should eq [31_i64, 41_i64]
      DEFAULT_HASH.decode("glSgV").should eq [13_i64, 89_i64]
    end

    it "returns empty array when decoding with the wrong salt" do
      peppers = EncodedId::Encoders::Hashid.new(EncodedId::Encoders::HashidSalt.new("this is my pepper"))
      DEFAULT_HASH.decode("NkK9").should eq [12345_i64]
      peppers.decode("NkK9").should eq [] of Int64
    end

    it "decodes from a min-length hash" do
      h = EncodedId::Encoders::Hashid.new(SALT, 8)
      h.decode("gB0NV05e").should eq [1_i64]
      h.decode("mxi8XH87").should eq [25_i64, 100_i64, 950_i64]
      h.decode("KQcmkIW8hX").should eq [5_i64, 200_i64, 195_i64, 1_i64]
    end

    it "raises InvalidInputError for malformed input" do
      expect_raises(EncodedId::InvalidInputError) do
        DEFAULT_HASH.decode("asdf-")
      end
    end

    it "returns [] of Int64 for an attacker-supplied long string that overflows Int64" do
      # Regression for CRIT §1: a 30-byte alphabet-only input would otherwise
      # overflow `Int64` inside `unhash` and escape as a 500. The public
      # `#decode` contract is now "garbage → empty array" for the overflow
      # case (specifically `DecodePayloadOverflowError`, a subclass of
      # `InvalidInputError`).
      encoder = EncodedId::Encoders::Hashid.new(EncodedId::Encoders::HashidSalt.new("x"))
      encoder.decode("a" * 30).should eq([] of Int64)
    end

    it "round-trips a value whose encoded form is later added to the blocklist" do
      # Regression for HIGH §2: `internal_decode`'s roundtrip-verify used the
      # public `encode`, which re-ran the blocklist check — so a record stored
      # before a word entered the blocklist would surface `BlocklistError` on
      # decode. The verify now uses `internal_encode`.
      salt = EncodedId::Encoders::HashidSalt.new("my-salt")
      plain = EncodedId::Encoders::Hashid.new(salt)
      encoded = plain.encode([42_i64])

      blocklist = EncodedId::Blocklist.new([encoded.downcase])
      guarded = EncodedId::Encoders::Hashid.new(
        salt,
        0,
        EncodedId::Alphabet.alphanum,
        blocklist,
        EncodedId::Encoders::BlocklistMode::Always,
      )

      guarded.decode(encoded).should eq([42_i64])
    end
  end

  describe "#unhash (private, exercised via TestableHashid)" do
    it "matches the published Ruby fixtures" do
      DEFAULT_HASH._unhash_for_spec("bb", "abc".chars.map(&.ord)).should eq 4
      DEFAULT_HASH._unhash_for_spec("aaa", "abc".chars.map(&.ord)).should eq 0
      DEFAULT_HASH._unhash_for_spec("cba", "abc".chars.map(&.ord)).should eq 21
      DEFAULT_HASH._unhash_for_spec("cbaabc", "abc".chars.map(&.ord)).should eq 572
      DEFAULT_HASH._unhash_for_spec("aX11b", "abcXYZ123".chars.map(&.ord)).should eq 2728
      DEFAULT_HASH._unhash_for_spec("abbd", "abcdefg".chars.map(&.ord)).should eq 59
      DEFAULT_HASH._unhash_for_spec("abcd", "abcdefg".chars.map(&.ord)).should eq 66
      DEFAULT_HASH._unhash_for_spec("acac", "abcdefg".chars.map(&.ord)).should eq 100
      DEFAULT_HASH._unhash_for_spec("acfg", "abcdefg".chars.map(&.ord)).should eq 139
      DEFAULT_HASH._unhash_for_spec("x21y", "xyz1234".chars.map(&.ord)).should eq 218
      DEFAULT_HASH._unhash_for_spec("yy44", "xyz1234".chars.map(&.ord)).should eq 440
      DEFAULT_HASH._unhash_for_spec("1xzz", "xyz1234".chars.map(&.ord)).should eq 1045
    end
  end
end
