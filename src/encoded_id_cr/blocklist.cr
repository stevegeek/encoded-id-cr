module EncodedId
  # A case-insensitive set of forbidden substrings for generated IDs. The
  # encoder calls `#blocks?(encoded)` after producing a candidate; if any
  # blocklist word appears as a substring (case-insensitively), the encoder
  # raises `BlocklistError`.
  #
  # Mirrors the Ruby gem's `EncodedId::Blocklist` semantics: `.empty` returns
  # an always-cached empty list; `.minimal` returns a small profanity set;
  # `#filter_for_alphabet` narrows the words to those buildable from a given
  # alphabet (used by Sqids in the Ruby gem to skip irrelevant entries).
  class Blocklist
    @words : Set(String)

    # Singletons for the two stateless factories. Mirrors Ruby's `@empty ||=`
    # / `@minimal ||=` memoisation on the metaclass.
    @@empty : Blocklist?
    @@minimal : Blocklist?

    MINIMAL_WORDS = [
      "ass", "cum", "fag", "fap", "fck", "fuk", "jiz", "pis", "poo", "sex",
      "tit", "xxx", "anal", "anus", "ball", "blow", "butt", "clit", "cock",
      "coon", "cunt", "dick", "dyke", "fart", "fuck", "jerk", "jizz", "jugs",
      "kike", "kunt", "muff", "nigg", "nigr", "piss", "poon", "poop", "porn",
      "pube", "pusy", "quim", "rape", "scat", "scum", "shit", "slut", "suck",
      "turd", "twat", "vag", "wank", "whor",
    ]

    def self.empty : Blocklist
      @@empty ||= new([] of String)
    end

    def self.minimal : Blocklist
      @@minimal ||= new(MINIMAL_WORDS)
    end

    def initialize(words : Enumerable(String) = [] of String)
      @words = words.map(&.to_s.downcase).to_set
    end

    # Returns a copy of the internal word set so callers can iterate / inspect
    # without being able to mutate the receiver. The memoised `.empty` /
    # `.minimal` singletons share their internal `@words` set process-wide, so
    # without the `.dup` here `Blocklist.minimal.words.add("x")` would corrupt
    # the singleton for every other caller in the process. (review §5)
    def words : Set(String)
      @words.dup
    end

    def each(&)
      @words.each { |word| yield word }
    end

    def to_a : Array(String)
      @words.to_a
    end

    def include?(word : String) : Bool
      @words.includes?(word.downcase)
    end

    # Returns the offending word as a `String` if the input contains any
    # blocked substring (case-insensitive), or `nil` otherwise.
    def blocks?(string : String) : String?
      return if @words.empty?
      downcased = string.downcase
      @words.each do |word|
        return word if downcased.includes?(word)
      end
      nil
    end

    def size : Int32
      @words.size
    end

    def empty? : Bool
      @words.empty?
    end

    def merge(other : Blocklist) : Blocklist
      Blocklist.new(@words.to_a + other.to_a)
    end

    # Drop words that:
    #   - are shorter than 3 characters (would catch too many false positives)
    #   - contain characters outside the alphabet (can never appear in output)
    def filter_for_alphabet(alphabet : Alphabet) : Blocklist
      filter_for_alphabet(alphabet.unique_characters)
    end

    def filter_for_alphabet(alphabet : String) : Blocklist
      filter_for_alphabet(alphabet.chars.map(&.to_s))
    end

    def filter_for_alphabet(alphabet_chars : Array(String)) : Blocklist
      alphabet_set = alphabet_chars.map(&.downcase).to_set
      Blocklist.new(
        @words.select do |word|
          word.size >= 3 && word.chars.all? { |char| alphabet_set.includes?(char.to_s) }
        end
      )
    end
  end
end
