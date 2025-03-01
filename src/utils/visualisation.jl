

function eosshow(io::IO, ::MIME"text/plain", model::EoSModel)
    print(io, typeof(model))
    model.lengthcomponents == 1 && println(io, " with 1 component:")
    model.lengthcomponents > 1 && println(io, " with ", model.lengthcomponents, " components:")
    for i in model.icomponents
        print(io, " \"", model.components[i], "\"")
        println(io)
    end
    print(io,"Contains parameters: ")
    firstloop = true
    for fieldname in fieldnames(typeof(model.params))
        firstloop == false && print(io, ", ")
        print(io, fieldname)
        firstloop = false
    end
end
function eosshow(io::IO, model::EoSModel)
    print(io, typeof(model))
    firstloop = true
    print(io, "(")
    for i in model.icomponents
        firstloop == false && print(io, ", ")
        print(io, "\"", model.components[i], "\"")
        firstloop = false
    end
    print(io, ")")
end

function Base.show(io::IO, ::MIME"text/plain", model::GCSAFTModel)
    print(io, typeof(model))
    model.lengthcomponents == 1 && println(io, " with 1 component:")
    model.lengthcomponents > 1 && println(io, " with ", model.lengthcomponents, " components:")
    for i in model.icomponents
        print(io, " \"", model.components[i], "\": ")
        firstloop = true
        for k in 1:length(model.allcomponentgroups[i])
            firstloop == false && print(io, ", ")
            print(io, "\"", model.allcomponentgroups[i][k], "\" => ", model.allcomponentngroups[i][k])
            firstloop = false
        end
        println(io)
    end
    print(io, "Contains parameters: ")
    firstloop = true
    for fieldname in fieldnames(typeof(model.params))
        firstloop == false && print(io, ", ")
        print(io, fieldname)
        firstloop = false
    end
end

function Base.show(io::IO, model::GCSAFTModel)
    print(io, typeof(model))
    firstloop = true
    for i in model.icomponents
        firstloop == false && print(io, ", ")
        print(io, "\"", model.components[i], "\"")
        firstloop = false
    end
    print(io, ")")
end
