module EncodedId
  # Represents a character set (alphabet) used for encoding IDs, with optional
  # character equivalences. Port of EncodedId::Alphabet from the Ruby gem.
  class Alphabet
    MIN_UNIQUE_CHARACTERS = 16

    # Factory: the modified Crockford Base32 alphabet, with the canonical
    # "look-alike" equivalences (o->0, i->j, l->1).
    def self.modified_crockford : Alphabet
      new(
        "0123456789abcdefghjkmnpqrstuvwxyz",
        {
          "o" => "0",
          "i" => "j",
          "l" => "1",
        }
      )
    end

    # Factory: alphanumeric (a-z, A-Z, 0-9), no equivalences.
    def self.alphanum : Alphabet
      new("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890")
    end

    getter unique_characters : Array(String)
    getter characters : String
    getter equivalences : Hash(String, String)?

    # Construct from a String of characters.
    def initialize(characters : String, equivalences : Hash(String, String)? = nil)
      raise InvalidAlphabetError.new("Alphabet must be a populated string or array") unless characters.size > 0
      @unique_characters = characters.chars.uniq.map(&.to_s)
      validate!(equivalences)
      @characters = @unique_characters.join
      @equivalences = equivalences
    end

    # Construct from an Array of single-character Strings.
    def initialize(characters : Array(String), equivalences : Hash(String, String)? = nil)
      raise InvalidAlphabetError.new("Alphabet must be a populated string or array") unless characters.size > 0
      @unique_characters = characters.uniq
      validate!(equivalences)
      @characters = @unique_characters.join
      @equivalences = equivalences
    end

    def include?(character : String) : Bool
      @unique_characters.includes?(character)
    end

    def to_a : Array(String)
      @unique_characters.dup
    end

    def to_s : String
      @characters.dup
    end

    def to_s(io : IO) : Nil
      io << @characters
    end

    def inspect(io : IO) : Nil
      io << "#<EncodedId::Alphabet chars: " << @unique_characters.inspect << ">"
    end

    def size : Int32
      @unique_characters.size
    end

    # Alias for `#size` (matches Ruby's `alias_method :length, :size`).
    def length : Int32
      size
    end

    private def validate!(equivalences : Hash(String, String)?)
      raise InvalidAlphabetError.new("Alphabet must not contain whitespace or null characters.") unless valid_characters?
      raise InvalidAlphabetError.new("Alphabet must contain at least #{MIN_UNIQUE_CHARACTERS} unique characters.") unless sufficient_characters?
      raise InvalidConfigurationError.new("Character equivalences must be a hash or nil and contain mappings to valid alphabet characters.") unless valid_equivalences?(equivalences)
    end

    # Mirrors Ruby's `unique_characters.grep(/\s|\0/).size == 0` -- reject any
    # entry containing whitespace or a null byte. Ruby's `\s` matches
    # `[ \t\n\r\f]` (no vertical tab), so we explicitly match that set instead
    # of using `Char#whitespace?` (which also accepts `\v`).
    private def valid_characters? : Bool
      return false if @unique_characters.empty?
      @unique_characters.none? do |c|
        c.each_char.any? do |ch|
          case ch
          when ' ', '\t', '\n', '\r', '\f', '\0' then true
          else                                        false
          end
        end
      end
    end

    private def sufficient_characters? : Bool
      @unique_characters.size >= MIN_UNIQUE_CHARACTERS
    end

    # Validates equivalences: keys/values must be 1-char strings, keys must NOT
    # already be in the alphabet, and values MUST be in the alphabet.
    private def valid_equivalences?(equivalences : Hash(String, String)?) : Bool
      return true if equivalences.nil?
      return false if equivalences.any? { |k, v| k.size != 1 || v.size != 1 }

      keys = equivalences.keys
      values = equivalences.values
      (@unique_characters & keys).empty? && (values - @unique_characters).empty?
    end
  end
end
