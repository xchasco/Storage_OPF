using CairoMakie

function graphManager(nN)
    # Determinar el tamaño de la malla (aproximadamente cuadrada)
    grid_size = ceil(Int, sqrt(nN))

    # Generar posiciones de los nodos en una cuadrícula
    nodos = [(i, j) for i in 1:grid_size for j in 1:grid_size][1:nN]

    # Crear gráfico
    fig, ax = scatter(first.(nodos), last.(nodos), markersize=10, color=:black)

    display(fig)
end