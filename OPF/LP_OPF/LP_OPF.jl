include("./Functions/dataManagerLP.jl")
include("./Functions/susceptanceMatrix.jl")

function LP_OPF(dLine::DataFrame, dGen::DataFrame, dNodes::Vector{DataFrame}, nN::Int, nL::Int, bMVA::Int, solver::String, hours::Int) 

    # dLine:    Line data
    # dGen:     Generator data
    # dNodes:   Demand data
    # nN:       Number of nodes
    # nL:       Number of lines
    # bMVA:     Base power
    # solver:   Solver to be used

    ########## DATA MANAGEMENT ##########
    P_Cost0, P_Cost1, P_Cost2, P_Gen_lb, P_Gen_ub, Gen_Status, P_Demand = dataManagerLP(dGen, dNodes, nN, bMVA)
    
    # Line susceptance matrix
    B = susceptanceMatrix(dLine, nN, nL)
    
    # Initialize lists to store results for all hours
    all_solGen = DataFrames.DataFrame()
    all_solFlows = DataFrames.DataFrame()
    all_solVoltage = DataFrames.DataFrame()
    costs_by_hour = DataFrames.DataFrame(hour = Int[], operation_cost = Float64[])

    # At the moment, we will use the last model to be managed by the code as a result. This could be change in the future
    lastm = nothing

    ########## LOOP FOR HOURS ##########
    for hour in 1:hours

        # Update dNodes to reflect demand for this hour (for now, we'll use the same)
        # Normally here you'd modify the demand for this hour
        P_Demand = dataManagerLP(dGen, dNodes, nN, bMVA)[7][hour]

        ########## INITIALIZE MODEL ##########
        # Create the "m" model with the JuMP.Model() function and
        # set the optimizer to use, in this case, the Gurobi solver
        if solver == "Gurobi"
            m = Model(Gurobi.Optimizer)
            # Disable default output from the optimizer
            set_silent(m)

        # For the HiGHS solver
        elseif solver == "HiGHS"
            m = Model(HiGHS.Optimizer)
            # Disable default output from the optimizer
            set_silent(m)

        # For the Ipopt solver
        elseif solver == "Ipopt"
            m = Model(Ipopt.Optimizer)
            # Disable default output from the optimizer
            set_silent(m)
        
        # In case of an error
        else
            println("ERROR: Solver selection in DC-OPF")
        
        end

        ########## VARIABLES ##########
        # Assign a generation variable for all nodes and initialize it to 0
        @variable(m, P_G[i in 1:nN], start = 0)

        # Assume the voltage magnitude at all nodes is constant (V = 1),
        # and only the angle varies
        @variable(m, θ[1:nN], start = 0)


        ########## OBJECTIVE FUNCTION ##########
        # The objective is to minimize the total cost calculated as ∑cᵢ·Pᵢ
        # Where:
        #   cᵢ is the cost of the Generator at node i
        #   Pᵢ is the power generated by the Generator at node i
        @objective(m, Min, sum(P_Cost0[i] + P_Cost1[i] * P_G[i]*bMVA + P_Cost2[i] * (P_G[i]*bMVA)^2 for i in 1:nN))


        ########## CONSTRAINTS ##########
        # Power flow constraint between nodes: P_G[i] - P_Demand[i] = ∑(B[i,j] · (θ[i] - θ[j]))
        # Where:
        #   P_G[i] is the power generated at node i
        #   P_Demand[i] is the power demanded at node i
        #   B[i,j] is the susceptance of the line connecting nodes i - j
        #   θ[i] - θ[j] is the angle difference between nodes i - j
        # The left-hand side represents the balance between Generated Power and Demanded Power.
        # If positive, the node supplies power to the grid;
        # if negative, it consumes power from the grid.
        # The right-hand side sums up all the flows passing through the node.
        @constraint(m, [i in 1:nN], P_G[i] - P_Demand[i] == sum(B[i, j] * (θ[i] - θ[j]) for j in 1:nN))

        # Maximum angle difference between two nodes connected by a line k
        for k in 1:nL
            if dLine.status[k] != 0
                @constraint(m, deg2rad(dLine.angmin[k]) <= θ[dLine.fbus[k]] - θ[dLine.tbus[k]] <= deg2rad(dLine.angmax[k]))
            end
        end

        # Maximum power flow on lines considering the line status
        # The power flow in the line connecting nodes i-j: Pᵢⱼ = Bᵢⱼ·(θᵢ-θⱼ)
        # Its absolute value must be less than the maximum power flow "dLine.rateA"
        for i in 1:nL
            if dLine.status[i] != 0
                @constraint(m, -dLine.rateA[i] / bMVA <= B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]]) <= dLine.rateA[i] / bMVA)
            end
        end

        # Minimum and maximum power generation considering the generator status
        @constraint(m, [i in 1:nN], P_Gen_lb[i] * Gen_Status[i] <= P_G[i] <= P_Gen_ub[i] * Gen_Status[i])

        # Select a reference node (node type = 3)
        # Necessary for HiGHS to avoid an infinite loop during optimization
        for i in 1:nrow(dNodes[hour])
            if dNodes[hour].type[i] == 3
                @constraint(m, θ[dNodes[hour].bus_i[i]] == 0)
            end
        end

        ########## SOLVING ##########
        JuMP.optimize!(m) # Optimization

        # Save solution to DataFrames if an optimal solution is found
        if termination_status(m) == OPTIMAL || termination_status(m) == LOCALLY_SOLVED || termination_status(m) == ITERATION_LIMIT

            # costs_by_hour includes results of costs for each hour analyzed
            push!(costs_by_hour, (hour = hour, operation_cost = objective_value(m)))

            # solGen stores the power generated by each generator in the network
            # First column: hour analyzed
            # Second column: node
            # Third column: value (from variable "P_G", in pu, converted to MVA)
            solGen = DataFrames.DataFrame(hour = hour, bus = (dGen.bus), powerGen = (value.(P_G[dGen.bus]) * bMVA))

            # solFlows stores the power flow through all lines
            # First column: originating node
            # Second column: destination node
            # Third column: power flow value in the line
            # solFlows = DataFrames.DataFrame(fbus = Int[], tbus = Int[], flow = Float64[])
            solFlows = DataFrames.DataFrame(hour = Int[], fbus = Int[], tbus = Int[], flow = Float64[])
            # The flow in the line connecting nodes i-j is equal to the susceptance of the line times the angle difference between nodes i-j
            # Pᵢⱼ = Bᵢⱼ · (θᵢ - θⱼ)
            #=
            for i in 1:nL
                if value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]])) > 0
                    push!(solFlows, Dict(:fbus => (dLine.fbus[i]), :tbus => (dLine.tbus[i]), :flow => round(value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]])) * bMVA, digits = 3)))
                elseif value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]])) != 0
                    push!(solFlows, Dict(:fbus => (dLine.tbus[i]), :tbus => (dLine.fbus[i]), :flow => round(value(B[dLine.tbus[i], dLine.fbus[i]] * (θ[dLine.tbus[i]] - θ[dLine.fbus[i]])) * bMVA, digits = 3)))
                end
            end
            =#
            for i in 1:nL
                if value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]])) > 0
                    push!(solFlows, Dict(:hour => hour, :fbus => dLine.fbus[i], :tbus => dLine.tbus[i], :flow => round(value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]])) * bMVA, digits = 3)))
                elseif value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]])) != 0
                    push!(solFlows, Dict(:hour => hour, :fbus => dLine.tbus[i], :tbus => dLine.fbus[i], :flow => round(value(B[dLine.tbus[i], dLine.fbus[i]] * (θ[dLine.tbus[i]] - θ[dLine.fbus[i]])) * bMVA, digits = 3)))
                end
            end

            # solVoltage stores the voltage magnitude and angle
            # First column: hour
            # Second column: node
            # Third column: voltage magnitude (1)
            # Fourth column: angle value in degrees
            #solVoltage = DataFrames.DataFrame(bus = Int[], voltageNode = Float64[], angleDegrees = Float64[])
            solVoltage = DataFrames.DataFrame(hour = Int[], bus = Int[], voltageNode = Float64[], angleDegrees = Float64[])
            #=
            for i in 1:nN
                push!(solVoltage, Dict(:bus => i, :voltageNode => 1,:angleDegrees => round(rad2deg(value(θ[i])), digits = 3)))
            end
            =#
            for i in 1:nN
                push!(solVoltage, Dict(:hour => hour, :bus => i, :voltageNode => 1, :angleDegrees => round(rad2deg(value(θ[i])), digits = 3)))
            end

            # Append results to the lists
                append!(all_solGen, solGen)
                append!(all_solFlows, solFlows)
                append!(all_solVoltage, solVoltage)

            ########## UPDATE THE MODEL ##########
            # we save the last model used
            lastm = m

        else
            println("No optimal solution found for hour $hour.")

            # If there is not an optimal solution for the analyzed hour, we dont include the operation cost of it.
            push!(costs_by_hour, (hour = hour, operation_cost = NaN))
        end
        
    end

    # Calculates and includes a new line for the total operational costs of all hours
    total_operation_cost = sum(skipmissing(costs_by_hour.operation_cost))
    push!(costs_by_hour, (hour = -1, operation_cost = total_operation_cost))

    # Return the model "m" and the generated DataFrames for generation, flows, and angles
    return lastm, all_solGen, all_solFlows, all_solVoltage, costs_by_hour
end