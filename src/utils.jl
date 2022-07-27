function getfirst(f::Function, itr)
    for i in itr
        if f(i)
            return i
        end
    end
    return nothing
end
