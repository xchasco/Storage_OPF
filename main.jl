# Load all Libraries
include("./Functions/loadLibraries.jl")

# Load all Functions
include("./Functions/loadFunctions.jl")

# First, tests are loaded for a faster solver load
# boot()

# Variable for loop end
endProgram = false
# In case we are not at the end of the program
while !endProgram

    # Clean Terminal
    clearTerminal()

    # Enter into a loop to select the study case
    case, opfType, s = selectStudyCase()

    # Clean Terminal
    clearTerminal()

    # Extract data from the study case
    # Where:
    #   data[1] = line data
    #   data[2] = generator data
    #   data[3] = demand data as a list of Dataframes
    #   data[4] = number of nodes
    #   data[5] = number of lines
    #   data[6] = base power
    #   data[7] = path to the .m file of the case
    #   data[8] = hours analyzed
    #   data[9] = solar data generated by each node
    #   data[10] = wind data generated by each node
    #   data[11] = data from batteries storage

    println("\nExtracting data...")
    data = extractData(case)
    println("Data extracted.")

    hours = data[8]

    # Once the study case is selected, call the corresponding function to solve the optimization problem
    println("\nGenerating OPF...")
    # In case of an DC-OPF
    if opfType == "DC-OPF"
        m, solGen, solFlows, solVoltage, solCosts, solCurt, solStorage = DC_OPF(data[1], data[2], data[3], data[4], data[5], data[6], s, hours, data[9], data[10], data[11])

    # In case of an AC-OPF
    elseif opfType == "AC-OPF"
        m, solGen, solFlows, solVoltage = AC_OPF(data[1], data[2], data[3], data[4], data[5], data[6], s)

    # If none of the above cases apply, return an error
    else
        println("ERROR: Failed to load OPF type")

    end

    # Clean terminal
    clearTerminal()

    # Optimization results management
    println("Problem solved")
    resultManager(m, solGen, solFlows, solVoltage, solCosts, solCurt, solStorage, data[7], opfType, s)

    # Ask the user if they want to continue the loop to study another case
    println("\nPress ENTER to continue or any other input to exit.")
    if readline() == ""
        # Keep the variable false to continue the loop
        endProgram = false
    else
        # Update the variable to exit the loop
        endProgram = true
        exit()
    end

end