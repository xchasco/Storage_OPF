function dataManagerLP(Generator::DataFrame, Node::DataFrame, nn::Int, bMVA::Int)

    # Generator:    DataFrame containing generator data
    # Node:         DataFrame containing node data
    # nn:           Number of nodes
    # bMVA:         Base power

    # The DataFrame passed as the "Generator" argument contains generator data from its corresponding file "generatorData.csv".
    # Explanation of sparsevec:
    # r = sparsevec(I, V, n) creates a list "r" where:
    #   Indices: given by the vector "I"
    #   Values: given by the vector "V"
    #   Total size: "n" elements
    # This means that r[I[k]] = V[k] for k ≤ n.

    # P_Cost is a sparsevec of "nn" elements that collects:
        # Indices: nodes where the generators are located "Generator.bus"
        # Values: cost of the respective generators
    # This means that the empty list of "nn" elements is filled with the cost values at the corresponding bus positions.
    # For example: If there is a generator at bus 3 with a cost of 10€/MWh, the list remains empty for elements 1 and 2, 
    # and a value of 10 is assigned to element 3.
    P_Cost0 = SparseArrays.sparsevec(Generator.bus, Generator.c0, nn)
    P_Cost1 = SparseArrays.sparsevec(Generator.bus, Generator.c1, nn)
    P_Cost2 = SparseArrays.sparsevec(Generator.bus, Generator.c2, nn)

    # P_Gen_lb and P_Gen_ub are sparsevecs of "nn" elements representing the lower and upper bounds, respectively, 
    # of the active power limits for the generators:
        # Indices: nodes where the generators are located "Generator.bus"
        # Values: lower bound "Generator.Pmin" or upper bound "Generator.Pmax" of the generator
    P_Gen_lb = SparseArrays.sparsevec(Generator.bus, Generator.Pmin / bMVA, nn)
    P_Gen_ub = SparseArrays.sparsevec(Generator.bus, Generator.Pmax / bMVA, nn)

    # The generator data considers inactive generators with status = 0.
    # A sparsevec is created to contain these values and account for switched-off generators.
    Gen_Status = SparseArrays.sparsevec(Generator.bus, Generator.status, nn)

    # The DataFrame passed as the "Node" argument contains demand data from its corresponding file "nodeData.csv".
    # P_Demand is a sparsevec of "nn" elements that collects:
        # Indices: nodes where the demand is located "Node.bus_i"
        # Values: demand at the respective nodes "Node.Pd"
    P_Demand = SparseArrays.sparsevec(Node.bus_i, Node.Pd / bMVA, nn)

    # The function returns all the generated SparseArrays as its output.
    return P_Cost0, P_Cost1, P_Cost2, P_Gen_lb, P_Gen_ub, Gen_Status, P_Demand

end