module EncodedId
  # Splits each hex string into the fewest chunks of at most 15 hex digits,
  # with lengths that differ by at most one. A chunk becomes the integer of its
  # digits prefixed with the hex digit 1 (more chunks follow) or 2 (last chunk
  # of the string), so leading zeros round-trip and every value stays below
  # `Encoders::Sqids::MAX_VALUE`.
  class TaggedHexRepresentation
    CHUNK_SIZE      = 15
    MORE_CHUNKS_TAG = '1'
    LAST_CHUNK_TAG  = '2'

    def hex_as_integers(hex : String) : Array(Int64)
      hex_as_integers([hex])
    end

    def hex_as_integers(hexes : Array(String)) : Array(Int64)
      if hexes.any?(&.empty?)
        raise ArgumentError.new("Empty hex string is not encodable (silent data loss); reject it before calling hex_as_integers")
      end
      hexes.flat_map { |hex_string| hex_string_as_integers(hex_string) }
    end

    # Returns `[]` unless the integers are exactly what encoding the decoded
    # strings gives, so each list of hex strings has a single ID.
    def integers_as_hex(integers : Array(Int64)) : Array(String)
      hex_strings = [] of String
      pending = String::Builder.new
      pending_length = 0
      chunk_count = 0
      first_length = 0
      previous_length = 0
      integers.each do |integer|
        tagged = integer.to_s(16)
        tag = tagged[0]
        return [] of String unless tag == MORE_CHUNKS_TAG || tag == LAST_CHUNK_TAG
        length = tagged.size - 1
        if chunk_count.zero?
          first_length = length
        elsif length > previous_length || length < first_length - 1
          return [] of String
        end
        chunk_count += 1
        previous_length = length
        pending << tagged[1..]
        pending_length += length
        next if tag == MORE_CHUNKS_TAG
        return [] of String unless chunk_count == chunk_count_for(pending_length)
        hex_strings << pending.to_s
        pending = String::Builder.new
        pending_length = 0
        chunk_count = 0
      end
      chunk_count.zero? ? hex_strings : [] of String
    end

    private def hex_string_as_integers(hex_string : String) : Array(Int64)
      cleaned = hex_string.gsub(/[^0-9a-fA-F]/, "").downcase
      raise InvalidInputError.new("Hex string #{hex_string.inspect} contains no hex digits") if cleaned.empty? && !hex_string.empty?

      chunk_count = chunk_count_for(cleaned.size)
      short_length, longer_chunks = cleaned.size.divmod(chunk_count)
      offset = 0
      Array(Int64).new(chunk_count) do |index|
        length = index < longer_chunks ? short_length + 1 : short_length
        tag = index == chunk_count - 1 ? LAST_CHUNK_TAG : MORE_CHUNKS_TAG
        chunk = cleaned[offset, length]
        offset += length
        "#{tag}#{chunk}".to_i64(16)
      end
    end

    private def chunk_count_for(length : Int32) : Int32
      Math.max((length + CHUNK_SIZE - 1) // CHUNK_SIZE, 1)
    end
  end
end
