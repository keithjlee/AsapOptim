using AsapOptim, Asap, AsapToolkit
using Zygote
using LinearSolve, LinearAlgebra

# frame Optimization
begin
    w_section = W("W460X158")
    @show w_section.name

    section = Section(
        Steel_kNm,
        w_section.A / 1e6,
        w_section.Ix / 1e12,
        w_section.Iy / 1e12,
        w_section.J / 1e12
    )
end;

# generate
begin
    Lx = 25.
    Ly = 15.
    nx = 10
    ny = 10

    # loads
    load = [0., 0., -20]

    gridframe = GridFrame(Lx, nx, Ly, ny, section; load = load, support = :xy)
    model = gridframe.model
    geo = Geo(model)
end

# design variables
begin

    @assert nx % 2 == 0 && ny % 2 == 0

    imidx = Int(nx / 2)
    imidy = Int(ny / 2)

    iparent = gridframe.igrid[2:imidx, 2:imidy]

    ichild1 = reverse(gridframe.igrid[2:imidx, imidy+1:end-1], dims = 2)
    factors1 = [-1., 1.]

    ichild2 = reverse(gridframe.igrid[imidx+1:end-1, 2:imidy], dims = 1)
    factors2 = [1., -1.]

    ichild3 = reverse(gridframe.igrid[imidx+1:end-1, imidy+1:end-1])
    factors3 = [-1., -1.]

    # make variables
    vars = Vector{FrameVariable}()

    fac = .9
    x = gridframe.dx * fac / 2
    y = gridframe.dy * fac / 2
    z = 1.5


    for i in eachindex(iparent)

        i0 = iparent[i]
        i1 = ichild1[i]
        i2 = ichild2[i]
        i3 = ichild3[i]


        # x
        push!(vars, SpatialVariable(model.nodes[i0], 0., -x, x, :X))
        ref = last(vars)

        push!(vars, CoupledVariable(model.nodes[i1], ref, factors1[1]))
        push!(vars, CoupledVariable(model.nodes[i2], ref, factors2[1]))
        push!(vars, CoupledVariable(model.nodes[i3], ref, factors3[1]))

        # y
        push!(vars, SpatialVariable(model.nodes[i0], 0., -y, y, :Y))
        ref = last(vars)

        push!(vars, CoupledVariable(model.nodes[i1], ref, factors1[2]))
        push!(vars, CoupledVariable(model.nodes[i2], ref, factors2[2]))
        push!(vars, CoupledVariable(model.nodes[i3], ref, factors3[2]))

        # z
        push!(vars, SpatialVariable(model.nodes[i0], 0.25, 0., z, :Z))
        ref = last(vars)

        push!(vars, CoupledVariable(model.nodes[i1], ref))
        push!(vars, CoupledVariable(model.nodes[i2], ref))
        push!(vars, CoupledVariable(model.nodes[i3], ref))
    end

    # explicitly run FrameOptParams2
    xyz = node_positions(model)
    X = xyz[:, 1]; Y = xyz[:, 2]; Z = xyz[:, 3]
    Ψ = getproperty.(model.elements, :Ψ)

    #Material properties
    sections = getproperty.(model.elements, :section)

    E = getproperty.(sections, :E)
    G = getproperty.(sections, :G)

    #Geometric properties
    A = getproperty.(sections, :A)
    Ix = getproperty.(sections, :Ix)
    Iy = getproperty.(sections, :Iy)
    J = getproperty.(sections, :J)

    #collectors
    vals = Vector{Float64}()
    lowerbounds = Vector{Float64}()
    upperbounds = Vector{Float64}()

    #index generation
    i = 1
    for var in vars

        if typeof(var) <: AsapOptim.IndependentVariable
            var.iglobal = i
            i += 1

            push!(vals, var.val)
            push!(lowerbounds, var.lb)
            push!(upperbounds, var.ub)
        end

    end

    #topology
    nodeids = getproperty.(model.elements, :nodeIDs)
    dofids = getproperty.(model.elements, :globalID)
    Conn = Asap.connectivity(model)
    freeids = model.freeDOFs

    #loads
    P = model.P
    Pf = model.Pf
end

# iactive = findall(model.nodes, :free)
# vars = [
#     [SpatialVariable(node, 0., -1.25, 1.25, :X) for node in model.nodes[iactive]];
#     [SpatialVariable(node, 0., -1.25, 1.25, :Y) for node in model.nodes[iactive]];
#     [SpatialVariable(node, 0.5, 0., 1., :Z) for node in model.nodes[iactive]]
#     ]

params = FrameOptParams(model, vars);

#objective function
function objective_function(x::Vector{Float64}, p::FrameOptParams)

    res = solve_frame(x, p)

    dot(res.U, p.P)
end

OBJ = x -> objective_function(x, params)
@time g = gradient(OBJ, params.values)[1]

using Nonconvex, NonconvexNLopt
Nonconvex.@load Ipopt

F = TraceFunction(OBJ)

omodel = Nonconvex.Model(F)
addvar!(
    omodel,
    params.lb,
    params.ub
)

alg = NLoptAlg(:LD_MMA)
opts = NLoptOptions(
    maxeval = 500,
    maxtime = 120,
    ftol_rel = 1e-8,
    xtol_rel = 1e-8,
    xtol_abs = 1e-8
)


alg = IpoptAlg()
opts = IpoptOptions(
    first_order = true,
    tol = 1e-6
)

@time res = optimize(
    omodel,
    alg,
    params.values,
    options = opts
)

@show length(F.trace)

using kjlMakie; set_theme!(kjl_light_mono)
model2 = updatemodel(params, res.minimizer)
geo2 = Geo(model2)

begin
    dfac = Observable(0.)

    pts = @lift(Point3.(geo.nodes .+ $dfac .* geo.disp))
    els = @lift($pts[$geo.indices_flat])

    pts2 = @lift(Point3.(geo2.nodes .+ $dfac .* geo2.disp))
    els2 = @lift($pts2[geo2.indices_flat])
end

#visualize
begin
    fig = Figure(
        backgroundcolor = :white
    )

    ax = Axis3(
        fig[1,1],
        aspect = :data
    )

    asapstyle!(ax; ground = true)

    linesegments!(
        els,
        color = (:black, .25)
    )

    linesegments!(
        els2,
        # color = abs.(geo2.Mz),
        # colormap = white2blue
    )

    # text!(
    #     pts,
    #     text = nvals
    # )

    sl = Slider(
        fig[2,1],
        startvalue = 0,
        range = range(0, 100, 250)
    )

    on(sl.value) do val
        dfac[] = val
    end

    on(dfac) do _
        autolimits!(ax)
    end

    fig
end 