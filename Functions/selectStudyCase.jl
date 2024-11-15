function selectStudyCase()

    while true
        # Study cases
        # Load the list of folders in the "Cases" directory into the "case" vector
        caseList = readdir("Cases")
        # Pass the list and name to the chooseOption function
        selectedCase = chooseOption(caseList, "case")

        # List of OPF types available for selection
        opfTypeList = ["LP-OPF", "AC-OPF"]
        opfType = chooseOption(opfTypeList, "type of OPF")

        # Based on the selected OPF type, ask for the solver to be used
        if opfType == "LP-OPF"
            lpSolversList = ["Gurobi", "HiGHS", "Ipopt"]
            solver = chooseOption(lpSolversList, "solver")

        elseif opfType == "AC-OPF"
            acSolversList = ["Ipopt", "Couenne"]
            solver = chooseOption(acSolversList, "solver")
            
        end

        # Clear the terminal
        clearTerminal()

        # Print a summary of all selected options in the terminal
        println("Summary:")
        println("Study case ---------- ", selectedCase)
        println("Type of OPF --------- ", opfType)
        println("Optimizer ----------- ", solver)

        # Ask the user if the listed options match their intentions; 
        # if not, they can reselect the options
        println("\nPress ENTER to continue or any other input to reselect.")
        response = readline()
        
        # If the response is "ENTER," proceed to continue and return the options
        if response == ""
            return selectedCase, opfType, solver
            break

        # Otherwise, cancel and return to selecting options
        else
            continue
            
        end
    
    end

end