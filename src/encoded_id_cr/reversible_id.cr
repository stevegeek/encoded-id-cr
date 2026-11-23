module EncodedId
  # High-level facade that ties an `Alphabet`, an encoder (`Encoders::Sqids` or
  # `Encoders::Hashid`), and the `CharHelpers` humanize/unhumanize passes into a
  # single `encode` / `decode` API matching the Ruby gem's
  # `EncodedId::ReversibleId`.
  #
  # Build via one of the factories:
  #
  #     id = EncodedId::ReversibleId.sqids
  #     id.encode(123)               # => "37vq-3u7t"
  #     id.decode("37vq-3u7t")       # => [123_i64]
  #
  #     hid = EncodedId::ReversibleId.hashid(salt: "my-salt")
  #     hid.encode(123)              # => "m3pm-8anj" (or similar)
  #     hid.decode("m3pm-8anj")      # => [123_i64]
  #
  # Defaults match the Ruby gem: modified-Crockford alphabet, separator "-"
  # inserted every 4 characters, max 32 inputs per encode, max output 128.
  class ReversibleId
    alias Encoder = Encoders::Sqids | Encoders::Hashid

    @encoder : Encoder
    @alphabet : Alphabet
    @split_at : Int32?
    @split_with : String
    @max_inputs_per_id : Int32
    @max_length : Int32?
    @hex_encoding : HexEncoding
    @legacy_hex : HexRepresentation
    @tagged_hex : TaggedHexRepresentation

    def self.sqids(
      alphabet : Alphabet = Alphabet.modified_crockford,
      min_length : Int32 = 8,
      blocklist : Blocklist | Array(String) = Blocklist.empty,
      blocklist_mode : Encoders::BlocklistMode = Encoders::BlocklistMode::LengthThreshold,
      blocklist_max_length : Int32 = 32,
      split_at : Int32? = 4,
      split_with : String = "-",
      max_inputs_per_id : Int32 = 32,
      max_length : Int32? = 128,
      hex_digit_encoding_group_size : Int32 = 4,
      hex_encoding : HexEncoding = HexEncoding::Tagged,
    ) : ReversibleId
      encoder = Encoders::Sqids.new(min_length, alphabet.characters, blocklist, blocklist_mode, blocklist_max_length)
      new(encoder, alphabet, split_at, split_with, max_inputs_per_id, max_length, hex_digit_encoding_group_size, hex_encoding)
    end

    def self.hashid(
      salt : String,
      alphabet : Alphabet = Alphabet.modified_crockford,
      min_hash_length : Int32 = 8,
      blocklist : Blocklist | Array(String) | Nil = nil,
      blocklist_mode : Encoders::BlocklistMode = Encoders::BlocklistMode::LengthThreshold,
      blocklist_max_length : Int32 = 32,
      split_at : Int32? = 4,
      split_with : String = "-",
      max_inputs_per_id : Int32 = 32,
      max_length : Int32? = 128,
      hex_digit_encoding_group_size : Int32 = 4,
      hex_encoding : HexEncoding = HexEncoding::Tagged,
    ) : ReversibleId
      bl = case blocklist
           when Blocklist     then blocklist
           when Array(String) then Blocklist.new(blocklist)
           when Nil           then nil
           end
      encoder = Encoders::Hashid.new(
        Encoders::HashidSalt.new(salt),
        min_hash_length,
        alphabet,
        bl,
        blocklist_mode,
        blocklist_max_length,
      )
      new(encoder, alphabet, split_at, split_with, max_inputs_per_id, max_length, hex_digit_encoding_group_size, hex_encoding)
    end

    def initialize(
      @encoder : Encoder,
      @alphabet : Alphabet,
      @split_at : Int32?,
      @split_with : String,
      @max_inputs_per_id : Int32,
      @max_length : Int32?,
      hex_digit_encoding_group_size : Int32 = 4,
      @hex_encoding : HexEncoding = HexEncoding::Tagged,
    )
      @legacy_hex = HexRepresentation.new(hex_digit_encoding_group_size)
      @tagged_hex = TaggedHexRepresentation.new
    end

    getter alphabet : Alphabet
    getter hex_encoding : HexEncoding

    def encode(value : Int) : String
      encode_int64s([value.to_i64])
    end

    # Elements may be integers, integral floats or base-10 integer strings;
    # anything else raises `InvalidInputError`.
    def encode(values : Array(T)) : String forall T
      encode_int64s(values.map { |value| integer_input(value) })
    end

    # Encode a hex string (UUIDs, hashes, etc.) with the configured
    # `hex_encoding` and encode the resulting list of integers.
    def encode_hex(hex : String) : String
      encode_hex([hex])
    end

    def encode_hex(hexes : Array(String)) : String
      encode_int64s(hex_representation(@hex_encoding).hex_as_integers(hexes))
    end

    # Decode a previously hex-encoded string back to the array of hex strings.
    # `scheme` overrides the configured `hex_encoding`, for example to read
    # IDs issued with `HexEncoding::Legacy` after switching to `Tagged`.
    def decode_hex(str : String, downcase : Bool = false, scheme : HexEncoding? = nil) : Array(String)
      hex_representation(scheme || @hex_encoding).integers_as_hex(decode(str, downcase: downcase))
    end

    def decode(str : String, downcase : Bool = false) : Array(Int64)
      raise EncodedIdFormatError.new("Max length of input exceeded") if max_length_exceeded?(str)

      unhumanized = CharHelpers.unhumanize(
        str,
        humanize? ? @split_with : nil,
        downcase,
        @alphabet.equivalences,
      )

      begin
        @encoder.decode(unhumanized)
      rescue ex : InvalidInputError
        raise EncodedIdFormatError.new(ex.message)
      end
    end

    private def encode_int64s(inputs : Array(Int64)) : String
      raise InvalidInputError.new("Cannot encode an empty array") if inputs.empty?
      raise InvalidInputError.new("Integer IDs to be encoded can only be positive") if inputs.any?(&.negative?)
      if inputs.size > @max_inputs_per_id
        raise InvalidInputError.new("#{inputs.size} integer IDs provided, maximum amount of IDs is #{@max_inputs_per_id}")
      end

      encoded = @encoder.encode(inputs)
      if (split_at = @split_at) && !@split_with.empty?
        encoded = CharHelpers.humanize_length(encoded, split_at, @split_with)
      end

      raise EncodedIdLengthError.new("Encoded ID exceeds max_length") if max_length_exceeded?(encoded)

      encoded
    end

    private def integer_input(value : Int) : Int64
      value.to_i64
    end

    private def integer_input(value : Float) : Int64
      unless value.finite? && value == value.trunc
        raise InvalidInputError.new("IDs to be encoded must be integers, got #{value.inspect}")
      end
      value.to_i64
    rescue OverflowError
      raise InvalidInputError.new("IDs to be encoded must fit in Int64, got #{value.inspect}")
    end

    private def integer_input(value : String) : Int64
      value.to_i64?(underscore: true) || raise InvalidInputError.new("IDs to be encoded must be integers, got #{value.inspect}")
    end

    private def hex_representation(scheme : HexEncoding) : HexRepresentation | TaggedHexRepresentation
      scheme.legacy? ? @legacy_hex : @tagged_hex
    end

    private def humanize? : Bool
      sa = @split_at
      !sa.nil? && !@split_with.empty?
    end

    private def max_length_exceeded?(str : String) : Bool
      ml = @max_length
      return false if ml.nil?
      str.size > ml
    end
  end
end
