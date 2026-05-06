require "./isolated_helper"

describe EncodedId::CharHelpers do
  describe ".humanize_length" do
    it "inserts the separator every split_at characters" do
      EncodedId::CharHelpers.humanize_length("abcdefgh", 4, "-").should eq("abcd-efgh")
    end

    it "does not insert a separator at the end" do
      # Length 8, split_at 4: only one separator (between groups), not after the last group.
      result = EncodedId::CharHelpers.humanize_length("abcdefgh", 4, "-")
      result.should_not end_with("-")
    end

    it "leaves strings shorter than split_at unchanged" do
      EncodedId::CharHelpers.humanize_length("abc", 4, "-").should eq("abc")
    end

    it "leaves strings exactly split_at long unchanged (boundary)" do
      EncodedId::CharHelpers.humanize_length("abcd", 4, "-").should eq("abcd")
    end

    it "inserts multiple separators for longer strings" do
      EncodedId::CharHelpers.humanize_length("abcdefghijkl", 4, "-").should eq("abcd-efgh-ijkl")
    end

    it "supports multi-character separators" do
      EncodedId::CharHelpers.humanize_length("abcdefgh", 4, "::").should eq("abcd::efgh")
    end

    it "handles split_at of 1" do
      EncodedId::CharHelpers.humanize_length("abcd", 1, "-").should eq("a-b-c-d")
    end

    it "handles non-multiple lengths (does not pad)" do
      EncodedId::CharHelpers.humanize_length("abcdefghij", 4, "-").should eq("abcd-efgh-ij")
    end
  end

  describe ".unhumanize" do
    it "strips the separator when given" do
      result = EncodedId::CharHelpers.unhumanize("abcd-efgh", "-", false, nil)
      result.should eq("abcdefgh")
    end

    it "leaves the input untouched when split_with is nil" do
      EncodedId::CharHelpers.unhumanize("abcd-efgh", nil, false, nil).should eq("abcd-efgh")
    end

    it "downcases when asked" do
      EncodedId::CharHelpers.unhumanize("ABCD-EFGH", "-", true, nil).should eq("abcdefgh")
    end

    it "does not downcase when not asked" do
      EncodedId::CharHelpers.unhumanize("ABCD-EFGH", "-", false, nil).should eq("ABCDEFGH")
    end

    it "applies equivalences (e.g. O -> 0 turns OOPS into 00ps)" do
      result = EncodedId::CharHelpers.unhumanize(
        "OOPS",
        nil,
        true,
        {"o" => "0"}
      )
      result.should eq("00ps")
    end

    it "applies multiple equivalences in sequence" do
      result = EncodedId::CharHelpers.unhumanize(
        "oilo",
        nil,
        false,
        {"o" => "0", "i" => "j", "l" => "1"}
      )
      result.should eq("0j10")
    end

    it "composes strip + downcase + equivalences" do
      result = EncodedId::CharHelpers.unhumanize(
        "OO-PS",
        "-",
        true,
        {"o" => "0"}
      )
      result.should eq("00ps")
    end
  end

  describe ".map_equivalent_characters" do
    it "returns the input unchanged when equivalences is nil" do
      EncodedId::CharHelpers.map_equivalent_characters("hello", nil).should eq("hello")
    end

    it "applies a single mapping via tr" do
      EncodedId::CharHelpers.map_equivalent_characters("oops", {"o" => "0"}).should eq("00ps")
    end
  end
end
