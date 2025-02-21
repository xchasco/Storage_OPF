include("./Functions/dataManagerLP.jl")
include("./Functions/susceptanceMatrix.jl")

function DC_OPF(dLine::DataFrame, dGen::DataFrame, dNodes::Vector{DataFrame}, nN::Int, nL::Int, bMVA::Int, solver::String, hours::Int, dSolar::DataFrame, dWind::DataFrame, dStorage::DataFrame)

    # dLine:    Line data
    # dGen:     Generator data
    # dNodes:   Demand data
    # nN:       Number of nodes
    # nL:       Number of lines
    # bMVA:     Base power
    # solver:   Solver to be used
    # dSolar:   Solar PV data

    ########## DATA MANAGEMENT ##########
    P_Cost0, P_Cost1, P_Cost2, P_Gen_lb, P_Gen_ub, Gen_Status, P_Demand, G_Solar, G_Wind, E_s_max, E_s_min, eta_c, eta_d, P_s_c_max, P_s_d_max = dataManagerLP(dGen, dNodes, nN, bMVA, hours, dSolar, dWind, dStorage)
    
    # Line susceptance matrix
    B = susceptanceMatrix(dLine, nN, nL)
    
    # Initialize lists to store results for all hours
    all_solGen = DataFrames.DataFrame(hour = Int[], bus = Int[], powerGen = Float64[])  # Power generated by each generator by hour
    all_solFlows = DataFrames.DataFrame(hour = Int[], fbus = Int[], tbus = Int[], flow = Float64[])  # Power flow through each line by hour
    all_solVoltage = DataFrames.DataFrame(hour=Int[], bus = Int[], voltageNode = Float64[], angleDegrees = Float64[])  # Voltage magnitude and angle by hour
    costs_by_hour = DataFrames.DataFrame(hour = Int[], operation_cost = Float64[])
    curtailment_results = DataFrames.DataFrame(hour = Int[], bus = Int[], P_curtailment = Float64[])
    storage_results = DataFrames.DataFrame(hour = Int[], bus = Int[], E_i = Float64[], E_s = Float64[])

    # At the moment, we will use the last model to be managed by the code as a result, just to make it work
    lastm = nothing

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
    @variable(m, P_G[i in 1:nN, t in 1:hours], start = 0)

    # Assume the voltage magnitude at all nodes is constant (V = 1),
    # and only the angle varies
    @variable(m, θ[i in 1:nN, t in 1:hours], start = 0)

    # We create the variables needed to stablish the curtailment. It represents Power that 
    # wont will be used in the system, for example, when Renewable power > Demand
    @variable(m, P_Curt[i in 1:nN, t in 1:hours], start = 0)

    # Energy storage variables
    @variable(m, E_s[i in 1:nN, t in 0:hours], start = 0)

    # Power of charging and discharging of the storage
    @variable(m, P_s_c[i in 1:nN, t in 1:hours], start = 0)
    @variable(m, P_s_d[i in 1:nN, t in 1:hours], start = 0)

    # Binary variable to indicate if the battery is charging or discharging
    @variable(m, y_s[i in 1:nN, t in 1:hours], Bin)

    ########## OBJECTIVE FUNCTION ##########
    # The objective is to minimize the total cost calculated as ∑cᵢ·Pᵢ
    # Where:
    #   cᵢ is the cost of the Generator at node i
    #   Pᵢ is the power generated by the Generator at node i
    @objective(m, Min, sum(P_Cost0[i] + P_Cost1[i] * P_G[i,t] * bMVA + P_Cost2[i] * (P_G[i,t] * bMVA)^2 for i in 1:nN, t in 1:hours)) ##AÑADIR TEMPORALIDAD AL COSTE??


    ################ CONSTRAINTS ################

    ### DEMAND = GENERATION ###
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
    @constraint(m, [i in 1:nN, t in 1:hours], P_G[i, t] .+ (G_Solar[i, t] .+ G_Wind[i, t] .- P_Curt[i, t]) .+ (P_s_d[i, t] .- P_s_c[i, t]) .- P_Demand[i, t] .== sum(B[i, j] * (θ[i, t] .- θ[j, t]) for j in 1:nN))

    ### CURTAILMENT ###
    # We include constraints related to solar curtailment
    # In case PRES + Ebat(t) > Pdemand or line exchange could not transfer all necessary power
    @constraint(m, [i in 1:nN, t in 1:hours], 0 <= P_Curt[i,t])
    @constraint(m, [i in 1:nN, t in 1:hours], P_Curt[i,t] <= G_Solar[i,t] + G_Wind[i,t] - P_s_c[i,t])

    ### ANGLE ###
    # Maximum angle difference between two nodes connected by a line k
    for k in 1:nL
        if dLine.status[k] != 0
            @constraint(m, [t in 1:hours], deg2rad(dLine.angmin[k]) <= θ[dLine.fbus[k],t] - θ[dLine.tbus[k],t] <= deg2rad(dLine.angmax[k])) ## AÑADIR TEMPORALIDAD AQUÍ?¿?¿
        end
    end


    ### POWER FLOW ###
    # Maximum power flow on lines considering the line status
    # The power flow in the line connecting nodes i-j: Pᵢⱼ = Bᵢⱼ·(θᵢ-θⱼ)
    # Its absolute value must be less than the maximum power flow "dLine.rateA"
    for k in 1:nL
        if dLine.status[k] != 0
            @constraint(m, [t in 1:hours],-dLine.rateA[k] / bMVA <= B[dLine.fbus[k], dLine.tbus[k]] * (θ[dLine.fbus[k],t] - θ[dLine.tbus[k],t]) <= dLine.rateA[k] / bMVA)
        end
    end


    ### "THERMAL" GENERATOR LIMITS ###
    # Minimum and maximum power generation considering the generator status
    @constraint(m, [i in 1:nN, t in 1:hours], P_Gen_lb[i] * Gen_Status[i] <= P_G[i,t] <= P_Gen_ub[i] * Gen_Status[i])


    ### REFERENCE NODE ###
    # Select a reference node (node type = 3)
    # Necessary for HiGHS to avoid an infinite loop during optimization
    for t in 1:hours
        for i in 1:nrow(dNodes[t])
            if dNodes[t].type[i] == 3
                @constraint(m, θ[dNodes[t].bus_i[i]] == 0)
            end
        end
    end

    ### STORAGE ###
    # Energy storage limits
    @constraint(m, [i in 1:nN, t in 1:hours], E_s_min[i] <= E_s[i,t] <= E_s_max[i])

    #Energy storage dynamics
    for i in 1:nN
        if eta_d[i] == 0 # We need this "if" in order not to divide by zero in nodes without storage
            eta_d[i] = 1
        end
    end

    for i in 1:nN
        @constraint(m, [i in 1:nN], E_s[i,0] == 0) #Necesario para tener un estado inicial de carga de las baterías. MODIFICAR ESTO PARA QUE PUEDA SER LEÍDO POR EL CÓDIGO AL PRINCIPIO
    end

    @constraint(m, [i in 1:nN, t in 1:hours], E_s[i,t] == E_s[i,t-1] + (eta_c[i] * P_s_c[i,t] - P_s_d[i,t] / eta_d[i]))
    
    # The charge and discharge constrained by the power limits of those batteries.
    # y_s is a binary variable that indicates if the battery is charging or discharging
    # y_s = 1: discharging
    # y_s = 0: charging
    @constraint(m, [i in 1:nN, t in 1:hours], 0 <= P_s_d[i,t])
    @constraint(m, [i in 1:nN, t in 1:hours], P_s_d[i,t] <= y_s[i,t] * P_s_d_max[i])

    @constraint(m, [i in 1:nN, t in 1:hours], 0 <= P_s_c[i,t])
    @constraint(m, [i in 1:nN, t in 1:hours], P_s_c[i,t] <= (1 - y_s[i,t]) * P_s_c_max[i])
    
    ########## SOLVING ##########
    JuMP.optimize!(m) # Optimization

    # Save solution to DataFrames if an optimal solution is found
    if termination_status(m) == OPTIMAL || termination_status(m) == LOCALLY_SOLVED || termination_status(m) == ITERATION_LIMIT

        for t in 1:hours
            # As we do a single OPF calculation for all the hours, if we want to know the cost of each hour, we need to do:
            operation_cost_t = sum(P_Cost0[i] + P_Cost1[i] * value(P_G[i, t]) * bMVA + P_Cost2[i] * (value(P_G[i, t]) * bMVA)^2 for i in 1:nN)

            # costs_by_hour includes results of costs for each hour analyzed
            push!(costs_by_hour, (hour = t, operation_cost = operation_cost_t))

            # solGen stores the power generated by each generator in the network
            # First column: hour analyzed
            # Second column: node
            # Third column: value (from variable "P_G", in pu, converted to MVA)
            solGen = DataFrames.DataFrame(hour = t, bus = (dGen.bus), powerGen = (value.(P_G[dGen.bus, t]) * bMVA))

            # solFlows stores the power flow through all lines
            # First column: originating node
            # Second column: destination node
            # Third column: power flow value in the line
            solFlows = DataFrames.DataFrame(hour = Int[], fbus = Int[], tbus = Int[], flow = Float64[])
            for i in 1:nL
                flow_value = value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i], t] - θ[dLine.tbus[i], t]) * bMVA)
                if flow_value > 0
                    push!(solFlows, Dict(:hour => t, :fbus => dLine.fbus[i], :tbus => dLine.tbus[i], :flow => round(value(B[dLine.fbus[i], dLine.tbus[i]] * (θ[dLine.fbus[i]] - θ[dLine.tbus[i]])) * bMVA, digits = 3)))
                elseif flow_value != 0
                    push!(solFlows, Dict(:hour => t, :fbus => dLine.tbus[i], :tbus => dLine.fbus[i], :flow => round(value(B[dLine.tbus[i], dLine.fbus[i]] * (θ[dLine.tbus[i]] - θ[dLine.fbus[i]])) * bMVA, digits = 3)))
                end
            end

            solVoltage = DataFrames.DataFrame(hour = Int[], bus = Int[], voltageNode = Float64[], angleDegrees = Float64[])
            # solVoltage stores the voltage magnitude and angle
            # First column: hour
            # Second column: node
            # Third column: voltage magnitude (1)
            # Fourth column: angle value in degrees
            for i in 1:nN
                push!(solVoltage, Dict(:hour => t, :bus => i, :voltageNode => 1, :angleDegrees => round(rad2deg(value(θ[i,t])), digits = 3)))
            end

            solCurt = DataFrames.DataFrame(hour = Int[], bus = Int[], P_curtailment = Float64[])
            # solCurt stores the curtailment of each node
            for i in 1:nN
                push!(solCurt, Dict(
                    :hour => t,
                    :bus => i,
                    :P_curtailment => round(value(P_Curt[i, t]) * bMVA, digits = 3)
                ))
            end

            # solStorage stores the state of charge of the storage
            # First column: hour
            # Second column: node
            # Third column: initial energy
            # Fourth column: final energy
            solStorage = DataFrames.DataFrame(hour = Int[], bus = Int[], E_i = Float64[], E_s = Float64[])
            for i in 1:nN
                push!(solStorage, Dict(
                    :hour => t,
                    :bus => i,
                    :E_i => round(value(E_s[i, t-1]), digits = 3),
                    :E_s => round(value(E_s[i, t]), digits = 3)
                ))
            end

            # Append results to the lists
                append!(all_solGen, solGen)
                append!(all_solFlows, solFlows)
                append!(all_solVoltage, solVoltage)
                append!(curtailment_results, solCurt)
                append!(storage_results, solStorage)

            ########## UPDATE THE MODEL ##########
            # we save the last model used
            lastm = m
        end

    else
        println("No optimal solution found for hour $hour.")

        # If there is not an optimal solution for the analyzed hour, we dont include the operation cost of it.
        for t in 1:hours
            push!(costs_by_hour, (hour = t, operation_cost = NaN))
        end
    end
        
    # Calculates and includes a new line for the total operational costs, that is the value of the objective function
    push!(costs_by_hour, (hour = -1, operation_cost = objective_value(m)))

    # Return the model "m" and the generated DataFrames for generation, flows, and angles
    return lastm, all_solGen, all_solFlows, all_solVoltage, costs_by_hour, curtailment_results, storage_results
end