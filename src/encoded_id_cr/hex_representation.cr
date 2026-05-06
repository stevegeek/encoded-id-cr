module EncodedId
  # Converts hex strings (UUIDs, hashes, anything matching `/[0-9a-f]+/i`) into
  # arrays of integers that can be fed into `Sqids` / `Hashid`, and back. This
  # is the bridge that lets the gem encode opaque hex values into short URL-
  # friendly tokens.
  #
  # Each hex string is chunked into groups of `hex_digit_encoding_group_size`
  # hex digits (4 hex digits per group means each integer fits in 16 bits).
  # Multiple hex strings are joined by a sentinel value (one greater than the
  # max representable group), which round-trips through encode/decode and is
  # used to re-split during `integers_as_hex`.
  #
  # Note vs the Ruby implementation: integers are kept in `Int64` rather than
  # Ruby's arbitrary-precision Integer, so `hex_digit_encoding_group_size` must
  # be small enough that the separator (2 ** (group_size * 4)) fits in Int64.
  # That means group_size must be ≤ 15 in practice. The constructor still
  # accepts up to 32 to match the Ruby API but raises if the value would
  # overflow.
  class HexRepresentation
    @hex_digit_encoding_group_size : Int32
    @hex_string_separator : Int64?

    def initialize(hex_digit_encoding_group_size : Int32)
      if hex_digit_encoding_group_size < 1 || hex_digit_encoding_group_size > 32
        raise InvalidConfigurationError.new("hex_digit_encoding_group_size must be > 0 and <= 32")
      end
      if hex_digit_encoding_group_size > 15
        raise InvalidConfigurationError.new(
          "hex_digit_encoding_group_size > 15 isn't supported in this Crystal port " \
          "(separator would overflow Int64); use a smaller group size"
        )
      end
      @hex_digit_encoding_group_size = hex_digit_encoding_group_size
    end

    # Convert one or more hex strings into a flat Array(Int64) suitable for
    # encoding. Multiple strings are joined by the sentinel separator.
    def hex_as_integers(hex : String) : Array(Int64)
      hex_as_integers([hex])
    end

    def hex_as_integers(hexes : Array(String)) : Array(Int64)
      digits_to_encode = [] of Int64
      hexes.each do |hex_string|
        digits_to_encode.concat(hex_string_as_integer_groups(hex_string))
        digits_to_encode << hex_string_separator
      end
      digits_to_encode.pop unless digits_to_encode.empty?
      digits_to_encode
    end

    # Reverse: convert a flat Array(Int64) back into the list of hex strings.
    def integers_as_hex(integers : Array(Int64)) : Array(String)
      hex_strings = [] of String
      hex_string = [] of String
      add_leading = false
      sep = hex_string_separator

      integers.reverse_each do |integer|
        if integer == sep
          hex_strings << hex_string.join
          hex_string = [] of String
          add_leading = false
        else
          hex_string << if add_leading
            # Zero-pad to maintain group size for non-leading groups.
            integer.to_s(16).rjust(@hex_digit_encoding_group_size, '0')
          else
            integer.to_s(16)
          end
          add_leading = true
        end
      end

      hex_strings << hex_string.join unless hex_string.empty?
      hex_strings.reverse
    end

    private def hex_string_separator : Int64
      @hex_string_separator ||= (2_i64 ** (@hex_digit_encoding_group_size * 4))
    end

    private def hex_string_as_integer_groups(hex_string : String) : Array(Int64)
      cleaned = hex_string.gsub(/[^0-9a-f]/i, "")
      convert_to_integer_groups(cleaned)
    end

    private def convert_to_integer_groups(hex_cleaned : String) : Array(Int64)
      # Mirror Ruby: walk the hex string in reverse, bucketing into groups of
      # the configured size, then unshift each char to keep the groups in the
      # correct (left-to-right within each group) order.
      groups = [] of Array(Char)
      hex_cleaned.chars.reverse!.each_with_index do |ch, idx|
        group_id = idx // @hex_digit_encoding_group_size
        while groups.size <= group_id
          groups << ([] of Char)
        end
        groups[group_id].unshift(ch)
      end
      groups.map(&.join.to_i64(16))
    end
  end
end
