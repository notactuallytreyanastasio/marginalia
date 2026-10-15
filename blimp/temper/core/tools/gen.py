import sys

HEADER = """# Blimp for the @connected declarations of core (sentences, reflow, segmenter).
#
# The backend splices this file in beside temper-core and gives each @connected
# declaration a body that calls `connected_<name>`. Every helper here is
# prefixed `core_` so that none of them can shadow a builtin.
#
# The class tables below are GENERATED, not written by hand. The script is
# blimp/temper/core/gen/dump.exs plus gen.py in the scratchpad of the commit
# that added this file; the data is what Elixir's own regexes say, taken by
# asking PCRE (with the `u` flag, as the sentence rules had) about every code
# point from U+0080 to U+10FFFF:
#   \\s   -> core_space_hi        \\p{Lu} -> core_upper_hi     \\d  -> core_digit_hi
#   \\p{L} -> core_letter_hi      \\p{N}  -> core_number_hi
#   String.upcase(cp) != cp -> core_upcase_changes_hi
# Each is a binary decision tree on the code point, so a lookup is about ten
# comparisons whatever the class. ASCII is answered before the tree is asked.

"""


def tree(rs, ind):
    pad = "  " * ind
    if len(rs) == 1:
        lo, hi = rs[0]
        return f"{pad}cp == {lo}\n" if lo == hi else f"{pad}cp >= {lo} and cp <= {hi}\n"
    m = len(rs) // 2
    out = f"{pad}case cp < {rs[m][0]} do\n"
    out += f"{pad}  true ->\n" + tree(rs[:m], ind + 2)
    out += f"{pad}  _ ->\n" + tree(rs[m:], ind + 2)
    out += f"{pad}end\n"
    return out


def main():
    data = {}
    for line in open(sys.argv[1]):
        name, n, body = line.rstrip("\n").split(" ", 2)
        rs = [tuple(int(x) for x in p.split("-")) for p in body.split(",")]
        assert len(rs) == int(n)
        data[name] = rs
    out = HEADER
    for name, rs in data.items():
        out += f"def core_{name}_hi(cp: Int) -> Any do\n" + tree(rs, 1) + "end\n\n"
    sys.stdout.write(out)


main()
