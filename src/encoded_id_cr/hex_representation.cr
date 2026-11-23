module EncodedId
  # How `ReversibleId#encode_hex` turns hex strings into integers: `Tagged`
  # (`TaggedHexRepresentation`, the default) or `Legacy` (`HexRepresentation`,
  # the scheme of the Ruby gem before 2.0).
  enum HexEncoding
    Legacy
    Tagged
  end

  # Converts hex strings (UUIDs, hashes, anything matching `/[0-9a-f]+/i`) into
  # arrays of integers that can be fed into `Sqids` / `Hashid`, and back. This
  # is the bridge that lets the gem encode opaque hex values into short URL-
  # friendly tokens.
  #
  # Each hex string is chunked into groups of `hex_digit_encoding_group_size`
  # hex digits (4 hex digits per group means each integer fits in 16 bits).
  # Multiple hex strings are joined by a sentinel value (one greater than the
  # max representable group), which round-trips through encode/decode and is
  # used to re-split during `integers_as_hex`. Values above the separator are
  # length markers: they record the digit count of a string's most significant
  # group, which the integers alone lose for leading zeros.
  class HexRepresentation
    MAX_HEX_DIGIT_ENCODING_GROUP_SIZE = 12

    @hex_digit_encoding_group_size : Int32
    @hex_string_separator : Int64

    def initialize(hex_digit_encoding_group_size : Int32)
      unless 1 <= hex_digit_encoding_group_size <= MAX_HEX_DIGIT_ENCODING_GROUP_SIZE
        raise InvalidConfigurationError.new(
          "hex_digit_encoding_group_size must be an integer in 1..#{MAX_HEX_DIGIT_ENCODING_GROUP_SIZE}"
        )
      end
      @hex_digit_encoding_group_size = hex_digit_encoding_group_size
      @hex_string_separator = 2_i64 ** (hex_digit_encoding_group_size * 4)
    end

    # Convert one or more hex strings into a flat Array(Int64) suitable for
    # encoding. Multiple strings are joined by the sentinel separator.
    def hex_as_integers(hex : String) : Array(Int64)
      hex_as_integers([hex])
    end

    def hex_as_integers(hexes : Array(String)) : Array(Int64)
      if hexes.any?(&.empty?)
        raise ArgumentError.new("Empty hex string is not encodable (silent data loss); reject it before calling hex_as_integers")
      end
      integer_representation(hexes)
    end

    # Reverse: convert a flat Array(Int64) back into the list of hex strings.
    # Returns `[]` unless the integers are exactly what encoding the decoded
    # strings gives.
    def integers_as_hex(integers : Array(Int64)) : Array(String)
      hex_strings = integers_to_hex_strings(integers)
      return [] of String unless canonical?(integers, hex_strings)
      hex_strings
    end

    private def integer_representation(hexes : Array(String)) : Array(Int64)
      digits_to_encode = [] of Int64
      hexes.each_with_index do |hex_string, index|
        digits_to_encode.concat(hex_string_as_integer_representation(hex_string, first: index.zero?))
        digits_to_encode << @hex_string_separator
      end
      digits_to_encode.pop unless digits_to_encode.empty?
      digits_to_encode
    end

    private def integers_to_hex_strings(integers : Array(Int64)) : Array(String)
      elements = [[] of Int64]
      integers.each do |integer|
        if integer == @hex_string_separator
          elements << ([] of Int64)
        else
          elements.last << integer
        end
      end

      hex_strings = [] of String
      elements.each_with_index do |groups, index|
        # IDs encoded before length markers existed give an empty first
        # string no groups, and it decodes to nothing as it did then.
        next if index.zero? && groups.empty?
        hex_string = groups_to_hex_string(groups)
        return [] of String if hex_string.nil?
        hex_strings << hex_string
      end
      hex_strings
    end

    # IDs issued before length markers existed start with a bare separator for
    # an empty first string, and still decode.
    private def canonical?(integers : Array(Int64), hex_strings : Array(String)) : Bool
      return true if hex_strings.empty?
      integer_representation(hex_strings) == integers ||
        integer_representation([""] + hex_strings).skip(1) == integers
    end

    private def groups_to_hex_string(groups : Array(Int64)) : String?
      return "" if groups.empty?

      most_significant_length = nil
      last_group = groups.last
      if last_group > @hex_string_separator
        return if last_group > length_marker(@hex_digit_encoding_group_size)
        most_significant_length = (last_group - length_marker(0)).to_i32
        groups = groups[0...-1]
      end
      return if groups.any? { |group| group > @hex_string_separator }

      most_significant = groups.last?
      return (most_significant_length == 0 ? "" : nil) if most_significant.nil?
      return if most_significant_length == 0

      leading = most_significant.to_s(16)
      if most_significant_length
        return if leading.size > most_significant_length
        leading = leading.rjust(most_significant_length, '0')
      end

      String.build do |io|
        io << leading
        groups[0...-1].reverse_each do |group|
          io << group.to_s(16).rjust(@hex_digit_encoding_group_size, '0')
        end
      end
    end

    private def hex_string_as_integer_representation(hex_string : String, first : Bool) : Array(Int64)
      cleaned = hex_string.gsub(/[^0-9a-f]/i, "")
      if cleaned.empty?
        raise InvalidInputError.new("Hex string #{hex_string.inspect} contains no hex digits") unless hex_string.empty?
        # Only a first empty string needs a marker: a later one already
        # round-trips as an empty slot between separators.
        return first ? [length_marker(0)] : [] of Int64
      end

      groups = convert_to_integer_groups(cleaned)
      most_significant_length = (cleaned.size - 1) % @hex_digit_encoding_group_size + 1
      return groups if groups.last.to_s(16).size == most_significant_length
      groups << length_marker(most_significant_length)
    end

    private def length_marker(length : Int32) : Int64
      @hex_string_separator + 1 + length
    end

    private def convert_to_integer_groups(hex_cleaned : String) : Array(Int64)
      # Mirror Ruby: walk the hex string in reverse, bucketing into groups of
      # the configured size, then unshift each char to keep the groups in the
      # correct (left-to-right within each group) order.
      groups = [] of Array(Char)
      hex_cleaned.chars.reverse!.each_with_index do |char, idx|
        group_id = idx // @hex_digit_encoding_group_size
        while groups.size <= group_id
          groups << ([] of Char)
        end
        groups[group_id].unshift(char)
      end
      groups.map(&.join.to_i64(16))
    end
  end
end
