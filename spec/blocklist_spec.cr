require "spec"
require "../src/encoded_id_cr"

describe EncodedId::Blocklist do
  describe ".empty" do
    it "is empty and matches nothing" do
      bl = EncodedId::Blocklist.empty
      bl.empty?.should be_true
      bl.size.should eq 0
      bl.to_a.should eq [] of String
      bl.include?("test").should be_false
      bl.blocks?("This is a test").should be_nil
    end

    it "is memoised" do
      EncodedId::Blocklist.empty.should be EncodedId::Blocklist.empty
    end

    it "doesn't leak mutations through #words to other callers (review §5)" do
      # Regression for MED §5: the memoised `.empty` / `.minimal` singletons
      # share their internal `@words` set process-wide. `words` must hand back
      # a copy so callers can't accidentally corrupt the singleton.
      first = EncodedId::Blocklist.empty.words
      first.add("trojan")
      EncodedId::Blocklist.empty.words.should be_empty
      EncodedId::Blocklist.empty.size.should eq 0
    end
  end

  describe ".minimal" do
    it "exposes a non-empty profanity list, case-insensitively" do
      bl = EncodedId::Blocklist.minimal
      bl.empty?.should be_false
      bl.size.should be > 0

      sample = bl.to_a.first
      bl.include?(sample).should be_true
      bl.include?(sample.upcase).should be_true
      bl.include?("hello").should be_false

      bl.blocks?("#{sample}-1234").should eq sample
      bl.blocks?("abcd#{sample.upcase}s").should eq sample
      bl.blocks?("Hello").should be_nil
    end

    it "doesn't leak mutations through #words to other callers (review §5)" do
      # Regression for MED §5: even on the canonical profanity list, callers
      # can't widen the singleton mid-process.
      original_size = EncodedId::Blocklist.minimal.size
      EncodedId::Blocklist.minimal.words.add("zzzzzz-not-a-real-word")
      EncodedId::Blocklist.minimal.size.should eq original_size
      EncodedId::Blocklist.minimal.include?("zzzzzz-not-a-real-word").should be_false
    end
  end

  describe "custom" do
    bl = EncodedId::Blocklist.new(["mxyj", "85m3", "ugly", "profane"])

    it "respects size and dedupes case" do
      bl.empty?.should be_false
      bl.size.should eq 4
      bl.to_a.should contain "ugly"
    end

    it "is case-insensitive on include?" do
      bl.include?("ugly").should be_true
      bl.include?("UGLY").should be_true
      bl.include?("nice").should be_false
    end

    it "returns the offending word from blocks?" do
      bl.blocks?("your-ugly").should eq "ugly"
      bl.blocks?("52sUGLYs1").should eq "ugly"
      bl.blocks?("nice").should be_nil
    end
  end

  describe "#filter_for_alphabet" do
    it "drops words that contain chars outside the alphabet" do
      bl = EncodedId::Blocklist.new(["abc", "az9", "xyz"])
      filtered = bl.filter_for_alphabet("abcdefghijklmnopqrstuvwxyz")
      filtered.to_a.sort.should eq ["abc", "xyz"]
    end

    it "drops words shorter than 3 characters" do
      bl = EncodedId::Blocklist.new(["ab", "abc"])
      filtered = bl.filter_for_alphabet("abcdefghij")
      filtered.to_a.should eq ["abc"]
    end
  end

  describe "Hashid integration" do
    salt = "test_salt_12345"
    custom_blocklist = EncodedId::Blocklist.new(["mxyj", "85m3", "ugly", "profane"])

    it "raises BlocklistError when the encoded id contains a blocked word" do
      reversible = EncodedId::ReversibleId.hashid(salt: salt, blocklist: custom_blocklist)
      # 124 should encode cleanly with this salt+blocklist combo
      reversible.encode(124).should_not be_empty
      # 123 happens to encode to a string containing one of the blocklist
      # words for this salt -- same case the Ruby gem's blocklist_test asserts.
      expect_raises(EncodedId::BlocklistError, /contains blocklisted word/) do
        reversible.encode(123)
      end
    end

    it "accepts an Array(String) shorthand" do
      reversible = EncodedId::ReversibleId.hashid(
        salt: salt,
        blocklist: ["mxyj", "85m3", "ugly", "profane"],
      )
      reversible.encode(124).should_not be_empty
      expect_raises(EncodedId::BlocklistError) { reversible.encode(123) }
    end

    it "honours :always mode regardless of length" do
      reversible = EncodedId::ReversibleId.hashid(
        salt: salt,
        blocklist: custom_blocklist,
        blocklist_mode: EncodedId::Encoders::BlocklistMode::Always,
        blocklist_max_length: 1, # would skip in :length_threshold mode
      )
      expect_raises(EncodedId::BlocklistError) { reversible.encode(123) }
    end

    it "skips checking when output exceeds blocklist_max_length under :length_threshold" do
      reversible = EncodedId::ReversibleId.hashid(
        salt: salt,
        blocklist: custom_blocklist,
        blocklist_max_length: 1,
      )
      reversible.encode(123).should_not be_empty
    end
  end
end
