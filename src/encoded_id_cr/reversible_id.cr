module EncodedId
  # High-level facade that ties an `Alphabet`, an encoder (`Encoders::Sqids` for
  # now -- Hashids would be a sibling), and the `CharHelpers` humanize/unhumanize
  # passes into a single `encode` / `decode` API matching the Ruby gem's
  # `EncodedId::ReversibleId`.
  #
  # Build via the `.sqids` factory:
  #
  #     id = EncodedId::ReversibleId.sqids
  #     id.encode(123)            # => "37vq-3u7t"  (humanized)
  #     id.decode("37vq-3u7t")    # => [123_i64]
  #
  # The factory's defaults match the Ruby gem: modified-Crockford alphabet,
  # min_length 8, separator "-" inserted every 4 characters, max 32 inputs per
  # encode, max output length 128.
  class ReversibleId
    @encoder : Encoders::Sqids
    @alphabet : Alphabet
    @split_at : Int32?
    @split_with : String
    @max_inputs_per_id : Int32
    @max_length : Int32?

    def self.sqids(
      alphabet : Alphabet = Alphabet.modified_crockford,
      min_length : Int32 = 8,
      blocklist : Array(String) = Encoders::Sqids::DEFAULT_BLOCKLIST,
      split_at : Int32? = 4,
      split_with : String = "-",
      max_inputs_per_id : Int32 = 32,
      max_length : Int32? = 128,
    ) : ReversibleId
      encoder = Encoders::Sqids.new(min_length, alphabet.characters, blocklist)
      new(encoder, alphabet, split_at, split_with, max_inputs_per_id, max_length)
    end

    def initialize(
      @encoder : Encoders::Sqids,
      @alphabet : Alphabet,
      @split_at : Int32?,
      @split_with : String,
      @max_inputs_per_id : Int32,
      @max_length : Int32?,
    )
    end

    getter alphabet : Alphabet

    # Encode a single integer.
    def encode(value : Int) : String
      encode_int64s([value.to_i64])
    end

    # Encode any array of integers (Int8/16/32/64). Normalised to Int64 at the
    # boundary so the encoder sees a homogeneous input.
    def encode(values : Array(T)) : String forall T
      encode_int64s(values.map(&.to_i64))
    end

    # Decode a (possibly humanized) ID back to an `Array(Int64)`.
    #
    # `downcase: true` will lowercase the input before applying equivalences --
    # useful when a user's URL got upper-cased somewhere along the way.
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
      rescue err : InvalidInputError
        raise EncodedIdFormatError.new(err.message)
      end
    end

    private def encode_int64s(inputs : Array(Int64)) : String
      raise InvalidInputError.new("Cannot encode an empty array") if inputs.empty?
      raise InvalidInputError.new("Integer IDs to be encoded can only be positive") if inputs.any?(&.negative?)
      if inputs.size > @max_inputs_per_id
        raise InvalidInputError.new("#{inputs.size} integer IDs provided, maximum amount of IDs is #{@max_inputs_per_id}")
      end

      encoded = @encoder.encode(inputs)
      encoded = CharHelpers.humanize_length(encoded, @split_at.not_nil!, @split_with) if humanize?

      raise EncodedIdLengthError.new("Encoded ID exceeds max_length") if max_length_exceeded?(encoded)

      encoded
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
