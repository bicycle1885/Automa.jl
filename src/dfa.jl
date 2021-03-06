# Deterministic Finite Automaton
# ==============================

type DFANode
    next::Dict{UInt8,Tuple{DFANode,Set{Action}}}
    eof_actions::Set{Action}
    final::Bool
    nfanodes::Set{NFANode}  # back reference to NFA nodes (optional)
end

function DFANode()
    return DFANode(Dict(), Set{Action}(), false, Set{NFANode}())
end

type DFA
    start::DFANode
end

function nfa2dfa(nfa::NFA)
    new_dfanode(S) = DFANode(Dict(), Set{Action}(), nfa.final ∈ S, S)
    S = epsilon_closure(Set([nfa.start]))
    start = new_dfanode(S)
    dfanodes = Dict([S => start])
    unvisited = [S]
    while !isempty(unvisited)
        S = pop!(unvisited)
        S_actions = accumulate_actions(S)
        for l in keyrange(S)
            T = epsilon_closure(move(S, l))
            if isempty(T)
                continue
            elseif !haskey(dfanodes, T)
                dfanodes[T] = new_dfanode(T)
                push!(unvisited, T)
            end
            actions = Set{Action}()
            for s in S
                if !haskey(s.trans, l)
                    continue
                end
                T′ = s.trans[l]
                for t in T′
                    union!(actions, s.actions[(l, t)])
                end
                if !isempty(T′)
                    union!(actions, S_actions[s])
                end
            end
            dfanodes[S].next[l] = (dfanodes[T], actions)
        end
        if nfa.final ∈ S
            dfanodes[S].eof_actions = S_actions[nfa.final]
        end
    end
    return DFA(start)
end

function keyrange(S::Set{NFANode})
    lo = 0xff
    hi = 0x00
    for s in S
        for l in bytekeys(s.trans)
            lo = min(l, lo)
            hi = max(l, hi)
        end
    end
    return lo:hi
end

function move(S::Set{NFANode}, label::UInt8)
    T = Set{NFANode}()
    for s in S
        if haskey(s.trans, label)
            union!(T, s.trans[label])
        end
    end
    return T
end

function epsilon_closure(S::Set{NFANode})
    closure = Set{NFANode}()
    unvisited = collect(S)
    while !isempty(unvisited)
        s = pop!(unvisited)
        push!(closure, s)
        for t in s.trans[:eps]
            if t ∉ closure
                push!(unvisited, t)
            end
        end
    end
    return closure
end

function accumulate_actions(S::Set{NFANode})
    top = copy(S)
    for s in S
        setdiff!(top, s.trans[:eps])
    end
    @assert !isempty(top)
    actions = Dict(s => Set{Action}() for s in S)
    visited = Set{NFANode}()
    unvisited = top
    while !isempty(unvisited)
        s = pop!(unvisited)
        push!(visited, s)
        for t in s.trans[:eps]
            union!(actions[t], union(actions[s], s.actions[(:eps, t)]))
            if t ∉ visited
                push!(unvisited, t)
            end
        end
    end
    return actions
end

function reduce_states(dfa::DFA)
    Q = all_states(dfa)
    distinct = distinct_states(Q)
    # reconstruct an optimized DFA
    equivalent(s) = filter(t -> (s, t) ∉ distinct, Q)
    new_dfanode(s) = DFANode(Dict(), Set{Action}(), s.final, Set{NFANode}())
    start = new_dfanode(dfa.start)
    S_start = equivalent(dfa.start)
    dfanodes = Dict(S_start => start)
    unvisited = [(S_start, start)]
    while !isempty(unvisited)
        S, s′ = pop!(unvisited)
        for s in S
            for (l, (t, as)) in s.next
                T = equivalent(t)
                if !haskey(dfanodes, T)
                    t′ = new_dfanode(t)
                    dfanodes[T] = t′
                    push!(unvisited, (T, t′))
                end
                s′.next[l] = (dfanodes[T], as)
            end
            s′.eof_actions = s.eof_actions
        end
    end
    return DFA(start)
end

function all_states(dfa::DFA)
    states = DFANode[]
    traverse(dfa) do s
        push!(states, s)
    end
    return states
end

function distinct_states(Q)
    actions = Dict{Tuple{DFANode,UInt8},Vector{Symbol}}()
    for q in Q, (l, (_, as)) in q.next
        actions[(q, l)] = sorted_unique_action_names(as)
    end

    distinct = Set{Tuple{DFANode,DFANode}}()
    function isdistinct(l, p, q)
        phasl = haskey(p.next, l)
        qhasl = haskey(q.next, l)
        if phasl && qhasl
            pl = p.next[l]
            ql = q.next[l]
            return (pl[1], ql[1]) ∈ distinct || actions[(p, l)] != actions[(q, l)]
        else
            return phasl != qhasl
        end
    end
    for p in Q, q in Q
        if p.final != q.final
            push!(distinct, (p, q))
        end
    end
    while true
        converged = true
        for p in Q, q in Q
            if (p, q) ∈ distinct
                continue
            end
            for l in 0x00:0xff
                if isdistinct(l, p, q)
                    push!(distinct, (p, q), (q, p))
                    converged = false
                    break
                end
            end
            if sorted_unique_action_names(p.eof_actions) != sorted_unique_action_names(q.eof_actions)
                push!(distinct, (p, q), (q, p))
                converged = false
            end
        end
        if converged
            break
        end
    end
    return distinct
end

function compact_labels(labels::Vector{UInt8})
    labels = sort(labels)
    labels′ = UnitRange{UInt8}[]
    while !isempty(labels)
        lo = shift!(labels)
        hi = lo
        while !isempty(labels) && first(labels) == hi + 1
            hi = shift!(labels)
        end
        push!(labels′, lo:hi)
    end
    return labels′
end

function dfa2nfa(dfa::DFA)
    =>(x, y) = (x, y)
    final = NFANode()
    nfanodes = Dict([dfa.start => NFANode()])
    unvisited = Set([dfa.start])
    while !isempty(unvisited)
        s = pop!(unvisited)
        for (l, (t, as)) in s.next
            @assert isa(l, UInt8)
            if !haskey(nfanodes, t)
                nfanodes[t] = NFANode()
                push!(unvisited, t)
            end
            addtrans!(nfanodes[s], l => nfanodes[t], as)
        end
        if s.final
            addtrans!(nfanodes[s], :eps => final, s.eof_actions)
        end
    end
    start = NFANode()
    addtrans!(start, :eps => nfanodes[dfa.start])
    return NFA(start, final)
end

function revoke_finals!(p::Function, dfa::DFA)
    visited = Set{DFANode}()
    unvisited = Set([dfa.start])
    while !isempty(unvisited)
        s = pop!(unvisited)
        push!(visited, s)
        if p(s)
            s.final = false
        end
        for (_, (t, _)) in s.next
            if t ∉ visited
                push!(unvisited, t)
            end
        end
    end
    return dfa
end

function remove_dead_states(dfa::DFA)
    backrefs = make_back_references(dfa)
    alive = Set{DFANode}()
    unvisited = Set([s for s in keys(backrefs) if s.final])
    while !isempty(unvisited)
        s = pop!(unvisited)
        push!(alive, s)
        for t in backrefs[s]
            if t ∉ alive
                push!(unvisited, t)
            end
        end
    end

    newnodes = Dict{DFANode,DFANode}(dfa.start => DFANode())
    unvisited = Set([dfa.start])
    while !isempty(unvisited)
        s = pop!(unvisited)
        s′ = newnodes[s]
        s′.eof_actions = s.eof_actions
        s′.final = s.final
        s′.nfanodes = s.nfanodes
        for (l, (t, as)) in s.next
            if t ∈ alive
                if !haskey(newnodes, t)
                    newnodes[t] = DFANode()
                    push!(unvisited, t)
                end
                s′.next[l] = (newnodes[t], as)
            end
        end
    end
    return DFA(newnodes[dfa.start])
end

function make_back_references(dfa::DFA)
    backrefs = Dict(dfa.start => Set{DFANode}())
    unvisited = Set([dfa.start])
    while !isempty(unvisited)
        s = pop!(unvisited)
        for (t, _) in values(s.next)
            if !haskey(backrefs, t)
                backrefs[t] = Set{DFANode}()
                push!(unvisited, t)
            end
            push!(backrefs[t], s)
        end
    end
    return backrefs
end
