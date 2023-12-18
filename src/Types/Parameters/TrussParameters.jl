"""
    TrussOptParams(model::TrussModel, variables::Vector{TrussVariable})

Contains all information and fields necessary for optimization.
"""
struct TrussOptParams <: AbstractOptParams
    model::TrussModel #the reference truss model for optimization
    values::Vector{Float64} #design variables
    indexer::TrussOptIndexer #pointers to design variables and full variables
    variables::Vector{TrussVariable}
    X::Vector{Float64} #all X coordinates |n_node|
    Y::Vector{Float64} #all Y coordinates |n_node|
    Z::Vector{Float64} #all Z coordinates |n_node|
    E::Vector{Float64} #all element young's modulii |n_element|
    A::Vector{Float64} #all element areas |n_element|
    P::Vector{Float64} # External load vector
    C::SparseMatrixCSC{Int64, Int64} #connectivity matrix
    lb::Vector{Float64} #lower bounds of variables
    ub::Vector{Float64} #upper bounds of variables
    cp::Vector{Int64} #S.colptr
    rv::Vector{Int64} #S.rowval
    nnz::Int64 #length(S.nzval)
    inzs::Vector{Vector{Int64}} # Indices of elemental K in global S.nzval
    freeids::Vector{Int64} # [DofFree1, DofFree2,...]
    nodeids::Vector{Vector{Int64}} # [[iNodeStart, iNodeEnd] for element in elements]
    dofids::Vector{Vector{Int64}} # [[dofStartNode..., dofEndNode...] for element in elements]
    n::Int64 #total number of DOFs

    function TrussOptParams(model::TrussModel, variables::Vector{TrussVariable})
        
        #model must be pre-proces
        model.processed || (Asap.process!(model))

        #extract global parameters
        xyz = node_positions(model)
        X = xyz[:, 1]; Y = xyz[:, 2]; Z = xyz[:, 3]
        E = getproperty.(getproperty.(model.elements, :section), :E)
        A = getproperty.(getproperty.(model.elements, :section), :A)

        #assign global id to variables
        vals = Vector{Float64}()
        lowerbounds = Vector{Float64}()
        upperbounds = Vector{Float64}()

        #assign an index to all unique variables, collect value and bounds
        i = 1
        for var in variables
            if typeof(var) <: IndependentVariable
                var.iglobal  = i
                i += 1
                push!(vals, var.val)
                push!(lowerbounds, var.lb)
                push!(upperbounds, var.ub)
            end
        end

        #generate indexer between design variables and truss parameters
        indexer = TrussOptIndexer(variables)

        #topology
        nodeids = getproperty.(model.elements, :nodeIDs)
        dofids = getproperty.(model.elements, :globalID)
        C = Asap.connectivity(model)
        freeids = model.freeDOFs

        #external load
        P = model.P

        #sparsity pattern of K
        inzs = all_inz(model)
        cp = model.S.colptr
        rv = model.S.rowval
        nnz = length(model.S.nzval)

        #generate a truss optimization problem
        new(model, 
            vals, 
            indexer, 
            variables, 
            X, 
            Y, 
            Z, 
            E, 
            A, 
            P,
            C,
            lowerbounds, 
            upperbounds,
            cp,
            rv,
            nnz,
            inzs,
            freeids,
            nodeids,
            dofids,
            model.nDOFs
            )

    end
end

"""
    TrussOptParamsNonalloc(model::TrussModel, variables::Vector{TrussVariable})

Contains all information and fields necessary for optimization.
"""
struct TrussOptParamsNonalloc <: AbstractOptParams
    model::TrussModel #the reference truss model for optimization
    values::Vector{Float64} #design variables
    indexer::TrussOptIndexer #pointers to design variables and full variables
    variables::Vector{TrussVariable} #variables for optimization
    lb::Vector{Float64} #lower bounds of variables
    ub::Vector{Float64} #upper bounds of variables
    E::Vector{Float64} #all element young's modulii |n_element|
    A::Vector{Float64} #all element areas |n_element|
    freeids::Vector{Int64} #DOF indices that are active
    P::Vector{Float64} # External load vector [active DOF only]
    C::SparseMatrixCSC{Int64, Int64} #connectivity matrix
    K::SparseMatrixCSC{Float64, Int64} #initial stiffness matrix
    cp::Vector{Int64} #K.colptr [active DOF only]
    rv::Vector{Int64} #K.rowval [active DOF only]
    inzs::Vector{Vector{Int64}} # Indices of elemental Kₑ in global K.nzval [active DOF only]
    i_dof_active::Vector{Vector{Int64}} #indices of elemental DOFs associated with reduced K
    i_k_active::Vector{Vector{Int64}} # Indices of row/columns in elemental Kₑ that are associated with a free DOF


    function TrussOptParamsNonalloc(model::TrussModel, variables::Vector{TrussVariable})
        
        #model must be pre-proces
        model.processed || (Asap.process!(model))

        #extract global parameters
        E = getproperty.(getproperty.(model.elements, :section), :E)
        A = getproperty.(getproperty.(model.elements, :section), :A)

        #assign global id to variables
        vals = Vector{Float64}()
        lowerbounds = Vector{Float64}()
        upperbounds = Vector{Float64}()

        #assign an index to all unique variables, collect value and bounds
        i = 1
        for var in variables
            if typeof(var) <: IndependentVariable
                var.iglobal  = i
                i += 1
                push!(vals, var.val)
                push!(lowerbounds, var.lb)
                push!(upperbounds, var.ub)
            end
        end

        #generate indexer between design variables and truss parameters
        indexer = TrussOptIndexer(variables)

        #topology
        C = Asap.connectivity(model)

        #activity of DOFs
        freeids = model.freeDOFs

        #external load
        P = model.P[freeids]

        #Stiffness matrix
        K = model.S[freeids, freeids]
        cp = K.colptr
        rv = K.rowval

        i_local, i_global = get_local_global_DOF_activity(model)

        inzs = [get_inz_reduced(cp, rv, id) for id in i_global]
        

        #generate a truss optimization problem
        new(model, 
            vals, 
            indexer, 
            variables, 
            lowerbounds, 
            upperbounds,
            E, 
            A, 
            freeids,
            P,
            C,
            K,
            cp,
            rv,
            inzs,
            i_global,
            i_local
            )

    end
end