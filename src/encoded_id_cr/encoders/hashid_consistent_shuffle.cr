module EncodedId
  module Encoders
    # Deterministic, salt-based shuffle that powers Hashids. Same algorithm as
    # the Ruby gem (which itself follows Hashids' classic walk-backwards swap):
    #
    #   for i = collection.size - 1 down to 1:
    #     n = salt[idx]            # cycling through salt_part_1, then salt_part_2
    #     ord_total += n
    #     j = (n + idx + ord_total) % i
    #     swap(collection[i], collection[j])
    #
    # `consistent_shuffle!` mutates `collection_to_shuffle` in place and also
    # returns it (for fluency).
    module HashidConsistentShuffle
      def consistent_shuffle!(
        collection_to_shuffle : Array(Int32),
        salt_part_1 : Array(Int32),
        salt_part_2 : Array(Int32)?,
        max_salt_length : Int32,
      ) : Array(Int32)
        salt_part_1_length = salt_part_1.size

        # MED §7: defensive size validation. Every internal caller passes a
        # correctly-sized buffer today; but historically only the nil-check on
        # salt_part_2 ran here, so a future caller passing an undersized
        # salt_part_2 (or a salt_part_1 shorter than max_salt_length with
        # `salt_part_2.size + salt_part_1.size < max_salt_length`) would crash
        # later with `IndexError` from the indexed access on line ~37 below.
        # Convert that into a useful `SaltError` up front.
        if salt_part_1_length < max_salt_length
          sp2 = salt_part_2
          if sp2.nil?
            raise SaltError.new("Salt is too short in shuffle")
          end
          required_part_2 = max_salt_length - salt_part_1_length
          if sp2.size < required_part_2
            raise SaltError.new(
              "Salt is too short in shuffle (salt_part_1.size=#{salt_part_1_length}, " \
              "salt_part_2.size=#{sp2.size}, max_salt_length=#{max_salt_length}; " \
              "need salt_part_2.size >= #{required_part_2})"
            )
          end
        end

        return collection_to_shuffle if collection_to_shuffle.empty? || max_salt_length == 0 || salt_part_1_length == 0

        idx = 0
        ord_total = 0_i64

        i = collection_to_shuffle.size - 1
        while i >= 1
          n = if idx >= salt_part_1_length
                sp2 = salt_part_2
                raise SaltError.new("Salt shuffle has failed") if sp2.nil?
                sp2[idx - salt_part_1_length]
              else
                salt_part_1[idx]
              end

          ord_total += n
          j = ((n.to_i64 + idx + ord_total) % i).to_i32
          collection_to_shuffle[i], collection_to_shuffle[j] = collection_to_shuffle[j], collection_to_shuffle[i]

          idx = (idx + 1) % max_salt_length
          i -= 1
        end

        collection_to_shuffle
      end
    end
  end
end
