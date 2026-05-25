module EncodedId
  module Encoders
    # Partitions the user-supplied alphabet into three disjoint character sets
    # used by the Hashid encoder:
    #
    #   1. alphabet  — the encoding base (target ratio alphabet : seps ≈ 3.5 : 1)
    #   2. seps      — separators inserted between encoded numbers
    #   3. guards    — boundary characters added to satisfy `min_hash_length`
    #                  (target ratio alphabet : guards ≈ 12 : 1)
    #
    # All three sets are stored as `Array(Int32)` codepoints.
    class HashidOrdinalAlphabetSeparatorGuards
      include HashidConsistentShuffle

      SEP_DIV      =  3.5
      GUARD_DIV    = 12.0
      DEFAULT_SEPS = "cfhistuCFHISTU".chars.map(&.ord)
      SPACE_CHAR   = ' '.ord

      getter alphabet : Array(Int32)
      getter seps : Array(Int32)
      getter guards : Array(Int32)
      getter salt : Array(Int32)
      getter seps_tr_selector : String
      getter guards_tr_selector : String

      def initialize(alphabet : Alphabet, salt : String)
        # MED §8: reject multibyte characters in the alphabet and salt for
        # consistency with Sqids (which already rejects them in
        # `validate_alphabet!`). Hashid downstream operations such as
        # `unsafe_chr.to_s` and the seasoning loop only behave correctly for
        # single-byte codepoints; previously multibyte input silently produced
        # mangled output. Raise `InvalidConfigurationError` (matching the
        # Sqids error class for alphabet-shape problems).
        alphabet.characters.each_char do |char|
          if char.bytesize > 1
            raise EncodedId::InvalidConfigurationError.new(
              "Hashid alphabet cannot contain multibyte characters"
            )
          end
        end
        salt.each_char do |char|
          if char.bytesize > 1
            raise EncodedId::InvalidConfigurationError.new(
              "Hashid salt cannot contain multibyte characters"
            )
          end
        end

        @alphabet = alphabet.characters.chars.map(&.ord)
        @salt = salt.chars.map(&.ord)
        @seps = [] of Int32
        @guards = [] of Int32
        @seps_tr_selector = ""
        @guards_tr_selector = ""

        setup_seps
        setup_guards

        @seps_tr_selector = escape_chars_for_tr(@seps.map(&.unsafe_chr.to_s))
        @guards_tr_selector = escape_chars_for_tr(@guards.map(&.unsafe_chr.to_s))
      end

      private def escape_chars_for_tr(chars : Array(String)) : String
        chars.join.gsub(/([\-\\^])/) { |match| "\\#{match}" }
      end

      private def setup_seps
        @seps = DEFAULT_SEPS.dup

        # Make alphabet and seps disjoint: keep a sep if it appears in alphabet
        # (and remove it from alphabet); otherwise drop it from seps. Using a
        # SPACE_CHAR placeholder lets us preserve indices while iterating.
        sep_index = 0
        while sep_index < @seps.size
          alphabet_index = @alphabet.index(@seps[sep_index])
          if alphabet_index
            @alphabet = remove_char_at(@alphabet, alphabet_index)
          else
            @seps = remove_char_at(@seps, sep_index)
          end
          sep_index += 1
        end

        @alphabet.reject!(SPACE_CHAR)
        @seps.reject!(SPACE_CHAR)

        salt_length = @salt.size
        consistent_shuffle!(@seps, @salt, nil, salt_length)

        alphabet_length = @alphabet.size
        seps_count = @seps.size
        if seps_count == 0 || (alphabet_length / seps_count.to_f) > SEP_DIV
          seps_target_count = (alphabet_length / SEP_DIV).ceil.to_i
          seps_target_count = 2 if seps_target_count == 1

          if seps_target_count > seps_count
            diff = seps_target_count - seps_count
            additional_seps = @alphabet[0, diff]
            @seps += additional_seps
            @alphabet = @alphabet[diff..]
          else
            @seps = @seps[0, seps_target_count]
          end
        end

        consistent_shuffle!(@alphabet, @salt, nil, salt_length)
      end

      private def setup_guards
        alphabet_length = @alphabet.size
        gc = (alphabet_length / GUARD_DIV).ceil.to_i

        if alphabet_length < 3
          @guards = @seps[0, gc]
          @seps = @seps.size > gc ? @seps[gc..] : [] of Int32
        else
          @guards = @alphabet[0, gc]
          @alphabet = @alphabet.size > gc ? @alphabet[gc..] : [] of Int32
        end
      end

      # Mirrors Ruby's `remove_character_at`: returns a NEW array where the
      # element at `index` is replaced by SPACE_CHAR (a placeholder that's
      # `Array#reject!`'d after the disjoint loop completes).
      private def remove_char_at(array : Array(Int32), index : Int32) : Array(Int32)
        head = array[0, index].dup
        head << SPACE_CHAR
        if index + 1 < array.size
          head + array[(index + 1)..]
        else
          head
        end
      end
    end
  end
end
