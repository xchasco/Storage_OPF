function extractData(c::String)
    # Line data
    lineData = CSV.read("Cases/$c/lineData.csv", DataFrame)

    # Generator data
    generatorData = CSV.read("Cases/$c/generatorData.csv", DataFrame)

    # Demand data
    nodeData = CSV.read("Cases/$c/nodeData.csv", DataFrame)

    # Number of nodes
    nNodes = maximum([lineData.fbus; lineData.tbus])

    # Number of lines
    nLines = size(lineData, 1)

    # Base power
    baseMVA = 100

    # Path to the .m file
    mFilePath = "Cases/$c/$c.m"

    if isfile(mFilePath)
        path = mFilePath
    else
        path = "None"
    end

    # Return all generated DataFrames and variables
    return(lineData, generatorData, nodeData, nNodes, nLines, baseMVA, path)
end