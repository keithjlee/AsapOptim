include("Utilities.jl")
export replacevalues
export addvalues

include("Geometry.jl")

include("Rtruss.jl")

include("Ktruss.jl")

include("K.jl")

include("Solve.jl")

include("Objective.jl")
export solvetruss
export compliance
export variation
export maxpenalty
export minpenalty
export volume

include("PostProcessing.jl")
export Faxial
export axialstress