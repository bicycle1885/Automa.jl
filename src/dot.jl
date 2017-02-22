# DOT Language
# ============

function nfa2dot(nfa::NFA)
    out = IOBuffer()
    println(out, "digraph {")
    println(out, "  graph [ rankdir = LR ];")
    println(out, "  0 -> 1;")
    println(out, "  0 [ shape = point ];")
    serials = Dict(s => i for (i, s) in enumerate(traverse(nfa.start)))
    for s in keys(serials)
        println(out, "  $(serials[s]) [ shape = $(s == nfa.final ? "doublecircle" : "circle") ];")
        for (e, t) in s.edges
            println(out, " $(serials[s]) -> $(serials[t]) [ label = \"$(edge2str(e))\" ];")
        end
    end
    println(out, "}")
    return String(take!(out))
end

function dfa2dot(dfa::DFA)
    out = IOBuffer()
    println(out, "digraph {")
    println(out, "  graph [ rankdir = LR ];")
    println(out, "  start -> 1;")
    println(out, "  start [ shape = point ];")
    serials = Dict(s => i for (i, s) in enumerate(traverse(dfa.start)))
    for s in keys(serials)
        println(out, "  $(serials[s]) [ shape = $(s.final ? "doublecircle" : "circle") ];")
        for (e, t) in s.edges
            println(out, "  $(serials[s]) -> $(serials[t]) [ label = \"$(edge2str(e))\" ];")
        end
        if !isempty(s.eof_actions)
            println(out, "  eof$(serials[s]) [ shape = point ];")
            println(out, "  $(serials[s]) -> eof$(serials[s]) [ label = \"$(eof_label(s.eof_actions))\", style = dashed ];")
        end
    end
    println(out, "}")
    return String(take!(out))
end

function edge2str(edge::Edge)
    out = IOBuffer()

    function printbyte(b, inrange)
        # TODO: does this work?
        if inrange && b == UInt8('-')
            print(out, "\\\\-")
        elseif inrange && b == UInt8(']')
            print(out, "\\\\]")
        else
            print(out, escape_string(b ≤ 0x7f ? escape_string(string(Char(b))) : @sprintf("\\x%x", b)))
        end
    end

    # output labels
    if isempty(edge.labels)
        print(out, 'ϵ')
    elseif length(edge.labels) == 1
        print(out, '\'')
        printbyte(first(edge.labels), false)
        print(out, '\'')
    else
        print(out, '[')
        for r in range_encode(edge.labels)
            if length(r) == 1
                printbyte(first(r), true)
            else
                @assert length(r) > 1
                printbyte(first(r), true)
                print(out, '-')
                printbyte(last(r), true)
            end
        end
        print(out, ']')
    end

    # output conditions
    if !isempty(edge.preconds)
        print(out, '(')
        join(out, (string(precond.value ? "" : "!", precond.name) for precond in edge.preconds), ',')
        print(out, ')')
    end

    # output actions
    if !isempty(edge.actions)
        print(out, '/')
        join(out, sorted_unique_action_names(edge.actions), ',')
    end

    return String(take!(out))
end

function eof_label(actions::Set{Action})
    out = IOBuffer()
    print(out, "EOF")
    if !isempty(actions)
        print(out, '/')
        join(out, sorted_unique_action_names(actions), ',')
    end
    return String(take!(out))
end
