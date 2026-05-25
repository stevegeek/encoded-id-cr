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
      # Shuffled alphabet, stored as codepoints (single-byte chars => Int32).
      @alphabet : Array(Int32)
      @min_length : Int32
      # Set for O(1) membership tests; lowercased for case-insensitive matching.
      @blocklist : Set(String)

      # Build a new encoder.
      #
      # `alphabet_chars` is the raw alphabet string (single-byte ASCII only).
      # The alphabet must contain unique characters and be at least 3 chars
      # long (canonical Sqids minimum). Duplicate characters silently break
      # round-trips; multibyte characters aren't supported. Other higher-level
      # alphabet semantics belong in the `Alphabet` wrapper.
      #
      # `blocklist` accepts either a `Blocklist` instance or a raw
      # `Array(String)`. Both flow through `Blocklist#filter_for_alphabet`,
      # which centralises the "size >= 3 AND only contains alphabet chars"
      # filter rule that Sqids and Hashid share. (review LOW dedup)
      def initialize(
        min_length : Int32,
        alphabet_chars : String,
        blocklist : Blocklist | Array(String) = DEFAULT_BLOCKLIST,
      )
        validate_alphabet!(alphabet_chars)
        validate_min_length!(min_length)

        alphabet_codepoints = alphabet_chars.chars.map(&.ord)

        # Reuse `Blocklist#filter_for_alphabet` so the alphabet-narrowing rule
        # lives in exactly one place (Blocklist itself). The filtered Blocklist
        # is then projected to a downcased `Set(String)` for O(1) membership
        # tests in `blocked_id?`.
        bl = blocklist.is_a?(Blocklist) ? blocklist : Blocklist.new(blocklist)
        @blocklist = bl.filter_for_alphabet(alphabet_chars).to_a.to_set

        @alphabet = shuffle(alphabet_codepoints)
        @min_length = min_length
      end

      # Encode a list of non-negative integers to a Sqids string.
      #
      # Returns `""` for an empty array. Raises `InvalidInputError` for any
      # negative input — matches the Ruby parent gem's behaviour and the
      # `ReversibleId` facade contract. Previously this returned `""` for
      # negative input, which disagreed with `ReversibleId#encode_int64s`
      # (raised) and meant the same library had two different contracts for
      # the same error condition. (review §9)
      def encode(numbers : Array(Int64)) : String
        return "" if numbers.empty?

        if numbers.any?(&.negative?)
          raise EncodedId::InvalidInputError.new(
            "encoded_id does not support negative integers"
          )
        end

        encode_numbers(numbers, 0)
      end

      # Decode a Sqids string back to its integers.
      #
      # Invalid characters or malformed input return an empty array (this is
      # the Ruby gem's contract — it never raises for bad strings).
      #
      # Decodes any input that produces a value ≤ `Int64::MAX`. Attacker-
      # controlled inputs ~30+ alphabet-only chars long can produce a base-N
      # reconstruction that exceeds `Int64::MAX`; that surfaces as
      # `DecodePayloadOverflowError` from `to_number` and is converted back to
      # an empty array here.
      def decode(s : String) : Array(Int64)
        ret = [] of Int64
        return ret if s.empty?

        id = s.chars.map(&.ord)

        # Reject any character not in our alphabet => empty array.
        id.each do |codepoint|
          return ret unless @alphabet.includes?(codepoint)
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
      rescue EncodedId::DecodePayloadOverflowError
        [] of Int64
      end

      # ----- private -----

      private def validate_alphabet!(alphabet_chars : String)
        # Crystal's String#chars iterates Unicode codepoints (Char). A multibyte
        # character has bytesize > 1 — the same predicate the Ruby gem uses.
        alphabet_chars.each_char do |char|
          if char.bytesize > 1
            raise EncodedId::InvalidInputError.new(
              "unable to create sqids instance: Alphabet cannot contain multibyte characters"
            )
          end
        end

        # Canonical Sqids minimum (matches the upstream reference impl).
        # Anything shorter cannot host the reserved separator + at least two
        # alphabet positions and would round-trip nonsense.
        if alphabet_chars.size < 3
          raise EncodedId::InvalidConfigurationError.new(
            "Sqids alphabet must be at least 3 chars"
          )
        end

        # Duplicate chars silently break encode/decode round-trips (the shuffle
        # picks one position deterministically, but `decode` walks linearly via
        # `Array#index`, so duplicates map to the wrong slot). Reject up front.
        # Use a Set to avoid the intermediate Array `chars.uniq` allocates.
        if alphabet_chars.each_char.to_set.size != alphabet_chars.size
          raise EncodedId::InvalidConfigurationError.new(
            "Sqids alphabet must contain unique characters"
          )
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
          # `i * j` is Int32 multiplication; safe for any alphabet size where
          # `length * length <= Int32::MAX` (~46_340 chars). Real-world Sqids
          # alphabets are 16–256 chars, so this assumption holds with room to
          # spare. If an alphabet ever exceeds ~46K chars, promote to Int64.
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
          id.each { |codepoint| io << codepoint.unsafe_chr }
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
      #
      # Raises `DecodePayloadOverflowError` when the reconstructed value would
      # exceed `Int64::MAX`. The public `#decode` method catches that and
      # returns an empty array (so attacker-supplied long-but-alphabet-valid
      # inputs cannot escape as a 500).
      private def to_number(id : Array(Int32), alphabet : Array(Int32)) : Int64
        alphabet_length = (alphabet.size - 1).to_i64
        id.reduce(0_i64) do |acc, codepoint|
          cp_index = alphabet.index(codepoint)
          # Should be unreachable — the public `decode` validates membership
          # before this is called — but match the Ruby gem's defensive raise.
          raise EncodedId::InvalidInputError.new("Character #{codepoint} not found in alphabet") if cp_index.nil?
          begin
            (acc * alphabet_length) + cp_index.to_i64 - 1
          rescue OverflowError
            raise EncodedId::DecodePayloadOverflowError.new("decoded payload exceeds Int64::MAX")
          end
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
