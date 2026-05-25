module EncodedId
  module Encoders
    # Hashid encoder ported from the optimised Ruby implementation. Encodes an
    # array of non-negative integers into a deterministic short string and
    # decodes it back. Uses a salt, a custom alphabet, and a minimum-length
    # padding scheme.
    #
    # Algorithm: Compute a "lottery" character from the input numbers; that
    # character + salt seasons the alphabet shuffle for each encoded number.
    # Numbers are joined by separators, padded with guards to reach the minimum
    # length, and verified on decode by re-encoding and comparing.
    #
    # `blocklist_mode` follows the Ruby gem:
    #   :length_threshold (default) -- only check ids whose length is <=
    #     blocklist_max_length (cheap, the case where humans most easily read
    #     the result)
    #   :always           -- check every id regardless of length
    enum BlocklistMode
      Always
      LengthThreshold
    end

    class Hashid
      include HashidConsistentShuffle

      getter alphabet_ordinals : Array(Int32)
      getter separator_ordinals : Array(Int32)
      getter guard_ordinals : Array(Int32)
      getter salt_ordinals : Array(Int32)
      getter salt : String
      getter alphabet : Alphabet
      getter min_hash_length : Int32
      getter blocklist : Blocklist?

      @separators_and_guards : HashidOrdinalAlphabetSeparatorGuards
      @escaped_separator_selector : String
      @escaped_guards_selector : String
      @blocklist_mode : BlocklistMode
      @blocklist_max_length : Int32

      def initialize(
        salt : HashidSalt,
        @min_hash_length : Int32 = 0,
        alphabet : Alphabet = Alphabet.alphanum,
        @blocklist : Blocklist? = nil,
        @blocklist_mode : BlocklistMode = BlocklistMode::LengthThreshold,
        @blocklist_max_length : Int32 = 32,
      )
        if @min_hash_length < 0
          raise ArgumentError.new("The min length must be a Integer and greater than or equal to 0")
        end

        @salt = salt.salt
        @alphabet = alphabet

        @separators_and_guards = HashidOrdinalAlphabetSeparatorGuards.new(alphabet, @salt)
        @alphabet_ordinals = @separators_and_guards.alphabet
        @separator_ordinals = @separators_and_guards.seps
        @guard_ordinals = @separators_and_guards.guards
        @salt_ordinals = @separators_and_guards.salt

        @escaped_separator_selector = @separators_and_guards.seps_tr_selector
        @escaped_guards_selector = @separators_and_guards.guards_tr_selector
      end

      # Encode an array of non-negative integers to a Hashid string.
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
          raise InvalidInputError.new("encoded_id does not support negative integers")
        end
        encoded = internal_encode(numbers)
        if check_blocklist?(encoded)
          if blocked = contains_blocklisted_word?(encoded)
            raise BlocklistError.new("Generated ID '#{encoded}' contains blocklisted word: '#{blocked}'")
          end
        end
        encoded
      end

      private def check_blocklist?(encoded : String) : Bool
        bl = @blocklist
        return false if bl.nil? || bl.empty?
        case @blocklist_mode
        when .always?           then true
        when .length_threshold? then encoded.size <= @blocklist_max_length
        else                         true
        end
      end

      private def contains_blocklisted_word?(encoded : String) : String?
        bl = @blocklist
        return if bl.nil?
        bl.blocks?(encoded)
      end

      # Decodes any input that produces a value ≤ `Int64::MAX`. Attacker-
      # controlled strings ~30+ alphabet-only chars long would otherwise
      # overflow the base-N reconstruction in `unhash`; those raise
      # `DecodePayloadOverflowError` from `unhash`, which we catch here and
      # convert to an empty array (matching the existing "garbage → empty"
      # contract Sqids exposes and avoiding a 500 in callers).
      def decode(hash : String) : Array(Int64)
        return [] of Int64 if hash.empty?
        internal_decode(hash)
      rescue DecodePayloadOverflowError
        [] of Int64
      end

      # Reconstruct a single integer from its base-N digit codepoints.
      #
      # **Internal — not part of the public API.** Specs reach this via a
      # test-only subclass that exposes a public `_unhash_for_spec` wrapper
      # (see `spec/encoders/hashid_spec.cr`).
      #
      # Raises `DecodePayloadOverflowError` (a subclass of `InvalidInputError`)
      # when the reconstructed value would exceed `Int64::MAX`. Inputs longer
      # than ~`log_base_N(Int64::MAX)` characters reliably overflow; the public
      # `#decode` method catches that and returns an empty array.
      private def unhash(input : String, alphabet : Array(Int32)) : Int64
        num = 0_i64
        input_length = input.size
        alphabet_length = alphabet.size
        i = 0

        while i < input_length
          first_char = input[i]
          pos = alphabet.index(first_char.ord)
          raise InvalidInputError.new("unable to unhash") if pos.nil?

          exponent = input_length - i - 1
          begin
            multiplier = (alphabet_length.to_i64) ** exponent
            num += pos.to_i64 * multiplier
          rescue OverflowError
            raise DecodePayloadOverflowError.new("decoded payload exceeds Int64::MAX")
          end
          i += 1
        end

        num
      end

      private def internal_encode(numbers : Array(Int64)) : String
        current_alphabet = @alphabet_ordinals.dup
        separator_ordinals = @separator_ordinals
        guard_ordinals = @guard_ordinals

        alphabet_length = current_alphabet.size
        length = numbers.size

        # Step 1: lottery
        hash_int = 0_i64
        i = 0
        while i < length
          hash_int += numbers[i] % (i + 100)
          i += 1
        end
        lottery = current_alphabet[(hash_int % alphabet_length).to_i32]

        hashid_code = [] of Int32
        hashid_code << lottery

        seasoning = [lottery] + @salt_ordinals
        alphabet_buffer = current_alphabet.dup

        # Step 2: per-number encoding with reshuffled alphabet
        i = 0
        while i < length
          num = numbers[i]
          alphabet_buffer.replace(current_alphabet)
          consistent_shuffle!(current_alphabet, seasoning, alphabet_buffer, alphabet_length)

          last_char_ord = hash_one_number(hashid_code, num, current_alphabet, alphabet_length)

          if (i + 1) < length
            num %= (last_char_ord + i)
            hashid_code << separator_ordinals[(num % separator_ordinals.size).to_i32]
          end

          i += 1
        end

        # Step 3: guards
        if hashid_code.size < @min_hash_length
          guard_count = guard_ordinals.size
          first_char = hashid_code[0]
          hashid_code.unshift(guard_ordinals[((hash_int + first_char) % guard_count).to_i32])

          if hashid_code.size < @min_hash_length
            third_char = hashid_code[2]?
            chosen = if third_char
                       guard_ordinals[((hash_int + third_char) % guard_count).to_i32]
                     else
                       guard_ordinals[(hash_int % guard_count).to_i32]
                     end
            hashid_code << chosen
          end
        end

        # Step 4: pad with shuffled alphabet
        half_length = alphabet_length // 2

        while hashid_code.size < @min_hash_length
          consistent_shuffle!(current_alphabet, current_alphabet.dup, nil, alphabet_length)

          second_half = current_alphabet[half_length..]
          first_half = current_alphabet[0, half_length]
          hashid_code = second_half + hashid_code + first_half

          excess = hashid_code.size - @min_hash_length
          if excess > 0
            hashid_code = hashid_code[excess // 2, @min_hash_length]
          end
        end

        ordinals_to_string(hashid_code)
      end

      # Decodes `hash` into the original integer array. Used by the public
      # `decode` (which wraps it with overflow handling).
      #
      # **Security note — review §10.** Encoded IDs are obfuscation, not
      # authentication. Do NOT use them as bearer tokens. The roundtrip-verify
      # below uses `!=` (not a constant-time compare) because the input is not
      # a secret — it's an obfuscated public identifier, and the comparison is
      # against a value derived from the user's own input. A timing side-channel
      # here would leak which characters round-trip correctly, but that gives
      # an attacker no useful capability (they already have the candidate
      # encoded id, and there's no secret to extract). If you need
      # authentication you should derive a separate token alongside (e.g. via
      # `marten-signed-id`) and never rely on encoded-id reversibility as a
      # security boundary.
      private def internal_decode(hash : String) : Array(Int64)
        ret = [] of Int64
        current_alphabet = @alphabet_ordinals.dup

        breakdown = hash.tr(@escaped_guards_selector, " ")
        array = breakdown.split(' ').reject(&.empty?)

        # Length 2 or 3 means guards split off the hash; the middle segment is
        # the actual encoded payload.
        i = (array.size == 3 || array.size == 2) ? 1 : 0

        if segment = array[i]?
          lottery_char = segment[0]
          remainder = segment.size > 1 ? segment[1..] : ""

          # Replace separators with spaces and split. Filter empties to match
          # Ruby's String#split(" ") whitespace-collapsing semantics.
          remainder = remainder.tr(@escaped_separator_selector, " ")
          sub_hashes = remainder.split(' ').reject(&.empty?)

          seasoning = [lottery_char.ord] + @salt_ordinals

          time = 0
          while time < sub_hashes.size
            sub_hash = sub_hashes[time]
            consistent_shuffle!(current_alphabet, seasoning, current_alphabet.dup, current_alphabet.size)
            ret << unhash(sub_hash, current_alphabet)
            time += 1
          end

          # Verify by re-encoding. If the round-trip doesn't match, the input
          # wasn't a valid hash for this configuration. We call
          # `internal_encode` here (not the public `encode`) so the roundtrip
          # check doesn't re-run the blocklist — otherwise an ID legitimately
          # stored before a word was added to the blocklist would surface as a
          # `BlocklistError` on decode instead of returning the original
          # numbers.
          if internal_encode(ret) != hash
            ret = [] of Int64
          end
        end

        ret
      end

      # Convert `num` into base-N (N = alphabet_length) and prepend each digit
      # to `hash_code`. Mirrors the Ruby `insert_at -= 1; hash_code.insert(...)`
      # idiom: starting at `insert_at = -1`, each new digit goes one step
      # further before the current end, producing most-significant-first order.
      private def hash_one_number(hash_code : Array(Int32), num : Int64, alphabet : Array(Int32), alphabet_length : Int32) : Int32
        char = 0
        insert_at = 0

        loop do
          char = alphabet[(num % alphabet_length).to_i32]
          insert_at -= 1
          hash_code.insert(insert_at, char)
          num //= alphabet_length
          break unless num > 0
        end

        char
      end

      # Convert an Array(Int32) of single-byte codepoints back into a String.
      # Equivalent to Ruby's `arr.pack("U*")` for the alphabets we support.
      private def ordinals_to_string(ords : Array(Int32)) : String
        String.build(ords.size) do |io|
          ords.each { |ord| io << ord.unsafe_chr }
        end
      end
    end
  end
end
