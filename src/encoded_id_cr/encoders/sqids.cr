require "./blocklist_default"

# Sqids (pronounced "squids") encodes an array of non-negative integers into a
# short, URL-friendly, reversible string. This is a Crystal port of the
# optimised `MySqids` Ruby implementation from the `encoded_id` gem.
#
# Algorithmic intent (kept identical to the Ruby source for byte-for-byte
# compatibility):
#   - The alphabet is shuffled deterministically using a self-referential mix
#     based on character code points, producing a permutation that depends only
#     on the alphabet itself.
#   - On encode, an offset is derived from the input numbers and the shuffled
#     alphabet, selecting a prefix character. The alphabet is then rotated by
#     that offset and reversed; this becomes the per-segment alphabet.
#   - Each number is base-encoded against the alphabet (excluding the first
#     character, which is reserved as the separator). Successive numbers are
#     joined by the first alphabet character; the alphabet is reshuffled
#     between segments so different segments use different mappings.
#   - If the result is shorter than `min_length`, padding from successive
#     reshuffles is appended.
#   - If the candidate ID matches a blocklisted word the entire process is
#     retried with `increment + 1`, advancing the offset until a clean ID is
#     produced (bounded by alphabet length).
#
# This Crystal port operates on `Int32` codepoints (single-byte alphabets only,
# which the constructor enforces) and `Int64` input numbers (Ruby's arbitrary-
# precision Integer is approximated; values must fit in `Int64`).
module EncodedId
  module Encoders
    class Sqids
      # Maximum integer value we support encoding. Ruby uses Integer::MAX
      # (arbitrary precision); Crystal's natural analog for typical IDs is
      # `Int64::MAX`. Numbers larger than this raise InvalidInputError.
      MAX_INT = Int64::MAX

      # Shuffled alphabet, stored as codepoints (single-byte chars => Int32).
      @alphabet : Array(Int32)
      @min_length : Int32
      # Set for O(1) membership tests; lowercased for case-insensitive matching.
      @blocklist : Set(String)

      # Build a new encoder.
      #
      # `alphabet_chars` is the raw alphabet string (single-byte ASCII only).
      # The caller-provided alphabet is taken at face value: we don't dedupe or
      # length-check beyond multibyte rejection (the Ruby tests only exercise
      # those two validations through this surface; additional validations
      # belong in the Alphabet wrapper a sibling agent owns).
      def initialize(min_length : Int32, alphabet_chars : String, blocklist : Array(String) = DEFAULT_BLOCKLIST)
        validate_alphabet!(alphabet_chars)
        validate_min_length!(min_length)

        alphabet_codepoints = alphabet_chars.chars.map(&.ord)

        # Filter the blocklist to only words that:
        #   - are at least 3 chars long
        #   - consist solely of (lowercased) characters present in the alphabet
        # then store as a downcased Set for fast lookup. Mirrors the Ruby gem's
        # filtering branch when a custom alphabet is supplied.
        downcased_alphabet = alphabet_chars.downcase.chars.to_set
        @blocklist = blocklist.compact_map do |word|
          next if word.size < 3
          downcased = word.downcase
          # All chars of the (downcased) word must exist in the alphabet.
          next unless downcased.each_char.all? { |c| downcased_alphabet.includes?(c) }
          downcased
        end.to_set

        @alphabet = shuffle(alphabet_codepoints)
        @min_length = min_length
      end

      # Encode a list of non-negative integers to a Sqids string.
      #
      # Returns "" for an empty array. Returns "" for any negative input
      # (matching the Ruby gem's behaviour, which filters negatives via
      # `between?(0, MAX_INT)` upstream — the Crystal test fixture asserts
      # `encode([-1])` is empty).
      def encode(numbers : Array(Int64)) : String
        return "" if numbers.empty?

        # Match Ruby behaviour: any negative number => return "" (Ruby filters
        # via `between?(0, MAX_INT)` and the test fixture for [-1] expects "").
        # Numbers above MAX_INT are impossible for Int64, but if a future
        # widening lets one through we'd raise InvalidInputError here.
        return "" if numbers.any?(&.negative?)

        encode_numbers(numbers, 0)
      end

      # Decode a Sqids string back to its integers.
      #
      # Invalid characters or malformed input return an empty array (this is
      # the Ruby gem's contract — it never raises for bad strings).
      def decode(s : String) : Array(Int64)
        ret = [] of Int64
        return ret if s.empty?

        id = s.chars.map(&.ord)

        # Reject any character not in our alphabet => empty array.
        id.each do |c|
          return ret unless @alphabet.includes?(c)
        end

        prefix = id[0]
        offset = @alphabet.index(prefix)
        return ret if offset.nil?

        alphabet = rotate_and_reverse_alphabet(@alphabet, offset)
        id = id[1..]

        while id.size > 0
          separator = alphabet[0]
          chunks = split_array(id, separator)
          if chunks.size > 0
            # An empty leading chunk indicates a malformed ID.
            return ret if chunks[0].empty?

            ret << to_number(chunks[0], alphabet)
            alphabet = shuffle(alphabet) if chunks.size > 1
          end

          id = (chunks.size > 1) ? chunks[1] : [] of Int32
        end

        ret
      end

      # ----- private -----

      private def validate_alphabet!(alphabet_chars : String)
        # Crystal's String#chars iterates Unicode codepoints (Char). A multibyte
        # character has bytesize > 1 — the same predicate the Ruby gem uses.
        alphabet_chars.each_char do |c|
          if c.bytesize > 1
            raise EncodedId::InvalidInputError.new(
              "unable to create sqids instance: Alphabet cannot contain multibyte characters"
            )
          end
        end
      end

      private def validate_min_length!(min_length : Int32)
        unless min_length >= 0 && min_length <= 255
          raise EncodedId::InvalidInputError.new(
            "unable to create sqids instance: Minimum length has to be between 0 and 255"
          )
        end
      end

      # Split `arr` at the first occurrence of `separator` into [before, after].
      # If the separator isn't present, returns `[arr]` (single element).
      private def split_array(arr : Array(Int32), separator : Int32) : Array(Array(Int32))
        index = arr.index(separator)
        return [arr] if index.nil?

        left = arr[0...index]
        right = arr[(index + 1)..]
        [left, right]
      end

      # Deterministic in-place shuffle. The same input always produces the same
      # output — that's what makes encode/decode reversible. Returns the same
      # array (not a copy) — callers that need isolation must dup() first.
      private def shuffle(chars : Array(Int32)) : Array(Int32)
        i = 0
        length = chars.size
        j = length - 1
        while j > 0
          r = ((i * j) + chars[i] + chars[j]) % length
          chars[i], chars[r] = chars[r], chars[i]
          i += 1
          j -= 1
        end
        chars
      end

      # Core encode loop with retry-on-blocklist. `increment` advances the
      # offset on each retry until a clean ID is produced.
      private def encode_numbers(numbers : Array(Int64), increment : Int32) : String
        alphabet_length = @alphabet.size
        if increment > alphabet_length
          raise EncodedId::InvalidInputError.new("Reached max attempts to re-generate the ID")
        end

        numbers_length = numbers.size
        # Offset starts as the count, then folds in each number's mapped char.
        offset = numbers_length.to_i64
        i = 0
        while i < numbers_length
          # numbers[i] % alphabet_length is non-negative for non-negative input.
          offset += @alphabet[(numbers[i] % alphabet_length.to_i64).to_i32].to_i64 + i
          i += 1
        end
        offset_i = (offset % alphabet_length.to_i64).to_i32
        offset_i = (offset_i + increment) % alphabet_length

        prefix = @alphabet[offset_i]
        # rotate_and_reverse_alphabet returns a fresh array — we mutate it
        # freely below via shuffle (which is in-place).
        alphabet = rotate_and_reverse_alphabet(@alphabet, offset_i)
        id = [prefix]

        i = 0
        while i < numbers_length
          to_id(id, numbers[i], alphabet)
          if i < numbers_length - 1
            id << alphabet[0]
            alphabet = shuffle(alphabet)
          end
          i += 1
        end

        if @min_length > id.size
          id << alphabet[0]
          while (@min_length - id.size) > 0
            alphabet = shuffle(alphabet)
            slice_length = Math.min(@min_length - id.size, alphabet.size)
            id.concat(alphabet[0, slice_length])
          end
        end

        result = String.build do |io|
          id.each { |cp| io << cp.unsafe_chr }
        end

        if blocked_id?(result)
          encode_numbers(numbers, increment + 1)
        else
          result
        end
      end

      # Encode `num` into `id` (in place) using `alphabet`. The first alphabet
      # character is reserved as separator, so the effective base is
      # `alphabet.size - 1` and we shift the produced index by +1.
      private def to_id(id : Array(Int32), num : Int64, alphabet : Array(Int32)) : Nil
        result = num
        start_index = id.size
        alphabet_length = (alphabet.size - 1).to_i64
        loop do
          new_char_index = (result % alphabet_length).to_i32 + 1
          new_char = alphabet[new_char_index]
          id.insert(start_index, new_char)
          result //= alphabet_length
          break if result <= 0
        end
      end

      # Inverse of to_id: read each codepoint as a digit in base `size - 1`.
      private def to_number(id : Array(Int32), alphabet : Array(Int32)) : Int64
        alphabet_length = (alphabet.size - 1).to_i64
        id.reduce(0_i64) do |a, v|
          v_index = alphabet.index(v)
          # Should be unreachable — the public `decode` validates membership
          # before this is called — but match the Ruby gem's defensive raise.
          raise EncodedId::InvalidInputError.new("Character #{v} not found in alphabet") if v_index.nil?
          (a * alphabet_length) + v_index.to_i64 - 1
        end
      end

      # The set of blocklist filtering rules:
      #   - skip words longer than the id (can't match)
      #   - very short id or word (<= 3): require exact match
      #   - word contains a digit: only match at the boundaries (start/end)
      #   - otherwise: substring match anywhere
      private def blocked_id?(id : String) : Bool
        id_down = id.downcase
        @blocklist.any? do |word|
          if word.size <= id_down.size
            if id_down.size <= 3 || word.size <= 3
              id_down == word
            elsif word.each_char.any?(&.ascii_number?)
              id_down.starts_with?(word) || id_down.ends_with?(word)
            else
              id_down.includes?(word)
            end
          else
            false
          end
        end
      end

      # Rotate `alphabet` left by `offset` positions, then reverse. Returns a
      # fresh array (caller may mutate freely).
      private def rotate_and_reverse_alphabet(alphabet : Array(Int32), offset : Int32) : Array(Int32)
        # Crystal's Array#rotate(n) returns a new rotated array (Ruby's
        # rotate! mutates; we don't want to mutate @alphabet).
        # Normalize offset for safety; modulo of any Int32 by size is in range.
        n = alphabet.size
        eff = offset % n
        rotated = alphabet.rotate(eff)
        rotated.reverse!
        rotated
      end
    end
  end
end
