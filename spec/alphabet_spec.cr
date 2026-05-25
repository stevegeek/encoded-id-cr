require "./spec_helper"

describe EncodedId::Alphabet do
  describe ".modified_crockford" do
    it "returns the expected character set" do
      alphabet = EncodedId::Alphabet.modified_crockford
      alphabet.characters.should eq("0123456789abcdefghjkmnpqrstuvwxyz")
      alphabet.size.should eq(33)
    end

    it "carries the canonical look-alike equivalences" do
      alphabet = EncodedId::Alphabet.modified_crockford
      alphabet.equivalences.should eq({
        "o" => "0",
        "i" => "j",
        "l" => "1",
      })
    end
  end

  describe ".alphanum" do
    it "is sized correctly (a-z, A-Z, 0-9 = 62 chars)" do
      alphabet = EncodedId::Alphabet.alphanum
      alphabet.size.should eq(62)
      alphabet.equivalences.should be_nil
    end
  end

  describe "#initialize (String input)" do
    it "constructs from a 16+ unique-character String" do
      alphabet = EncodedId::Alphabet.new("0123456789abcdef")
      alphabet.size.should eq(16)
      alphabet.characters.should eq("0123456789abcdef")
    end

    it "deduplicates characters (matches Ruby String#chars.uniq)" do
      alphabet = EncodedId::Alphabet.new("0123456789abcdefa")
      alphabet.size.should eq(16)
      alphabet.unique_characters.should eq(%w[0 1 2 3 4 5 6 7 8 9 a b c d e f])
    end
  end

  describe "#initialize (Array(String) input)" do
    it "constructs from an Array of single-character Strings" do
      chars = %w[0 1 2 3 4 5 6 7 8 9 a b c d e f]
      alphabet = EncodedId::Alphabet.new(chars)
      alphabet.size.should eq(16)
      alphabet.unique_characters.should eq(chars)
    end

    it "rejects multi-character entries (review §4)" do
      # Regression for MED §4: previously `Alphabet.new(["abc","def"])` silently
      # constructed a misshapen alphabet whose `size` lied.
      expect_raises(EncodedId::InvalidAlphabetError, /single-character/) do
        EncodedId::Alphabet.new(["abc", "def"])
      end
    end

    it "rejects empty-string entries" do
      expect_raises(EncodedId::InvalidAlphabetError, /single-character/) do
        EncodedId::Alphabet.new(["a", "", "b"])
      end
    end
  end

  describe "validation" do
    it "rejects an empty string" do
      expect_raises(EncodedId::InvalidAlphabetError, "populated") do
        EncodedId::Alphabet.new("")
      end
    end

    it "rejects an empty array" do
      expect_raises(EncodedId::InvalidAlphabetError, "populated") do
        EncodedId::Alphabet.new([] of String)
      end
    end

    it "rejects whitespace characters (space)" do
      bad = "0123456789abcde" + " "
      expect_raises(EncodedId::InvalidAlphabetError, "whitespace") do
        EncodedId::Alphabet.new(bad)
      end
    end

    it "rejects whitespace characters (tab)" do
      bad = "0123456789abcde" + "\t"
      expect_raises(EncodedId::InvalidAlphabetError, "whitespace") do
        EncodedId::Alphabet.new(bad)
      end
    end

    it "rejects null bytes" do
      bad = "0123456789abcde" + Char::ZERO.to_s
      expect_raises(EncodedId::InvalidAlphabetError, "whitespace") do
        EncodedId::Alphabet.new(bad)
      end
    end

    it "rejects fewer than 16 unique characters" do
      expect_raises(EncodedId::InvalidAlphabetError, "16 unique") do
        EncodedId::Alphabet.new("0123456789abcde")
      end
    end

    it "rejects when post-dedup uniques fall below 16" do
      # 16 characters but only 15 unique (final 'e' is a repeat)
      expect_raises(EncodedId::InvalidAlphabetError, "16 unique") do
        EncodedId::Alphabet.new("0123456789abcdee")
      end
    end
  end

  describe "equivalences validation" do
    it "rejects multi-char equivalence keys" do
      expect_raises(EncodedId::InvalidConfigurationError) do
        EncodedId::Alphabet.new("0123456789abcdef", {"oo" => "0"})
      end
    end

    it "rejects multi-char equivalence values" do
      expect_raises(EncodedId::InvalidConfigurationError) do
        EncodedId::Alphabet.new("0123456789abcdef", {"o" => "00"})
      end
    end

    it "rejects keys that are already in the alphabet" do
      # "a" is in the alphabet, so it can't be an equivalence key
      expect_raises(EncodedId::InvalidConfigurationError) do
        EncodedId::Alphabet.new("0123456789abcdef", {"a" => "0"})
      end
    end

    it "rejects values that are NOT in the alphabet" do
      # "z" is not in the alphabet, so it can't be an equivalence target
      expect_raises(EncodedId::InvalidConfigurationError) do
        EncodedId::Alphabet.new("0123456789abcdef", {"o" => "z"})
      end
    end

    it "accepts valid equivalences" do
      alphabet = EncodedId::Alphabet.new("0123456789abcdef", {"o" => "0"})
      alphabet.equivalences.should eq({"o" => "0"})
    end
  end

  describe "#include?" do
    it "returns true for characters in the alphabet" do
      alphabet = EncodedId::Alphabet.modified_crockford
      alphabet.include?("0").should be_true
      alphabet.include?("z").should be_true
    end

    it "returns false for characters not in the alphabet" do
      alphabet = EncodedId::Alphabet.modified_crockford
      alphabet.include?("o").should be_false
      alphabet.include?("i").should be_false
      alphabet.include?("l").should be_false
    end
  end

  describe "#size and #length" do
    it "agree" do
      alphabet = EncodedId::Alphabet.modified_crockford
      alphabet.size.should eq(alphabet.length)
    end
  end

  describe "#to_a" do
    it "returns a copy of unique_characters" do
      alphabet = EncodedId::Alphabet.modified_crockford
      arr = alphabet.to_a
      arr.should eq(alphabet.unique_characters)
      arr.should_not be(alphabet.unique_characters)
    end
  end

  describe "#to_s" do
    it "returns the joined character string" do
      alphabet = EncodedId::Alphabet.modified_crockford
      alphabet.to_s.should eq("0123456789abcdefghjkmnpqrstuvwxyz")
    end
  end
end
