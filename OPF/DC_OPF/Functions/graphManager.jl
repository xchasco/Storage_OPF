using PyPlot

function graphManager(nN)
    # Determinar el tamaño de la malla (aproximadamente cuadrada)
    grid_size = ceil(Int, sqrt(nN))

    # Generar posiciones de los nodos en una cuadrícula
    all_nodes = [(i, j) for i in 1:grid_size for j in 1:grid_size]

    # Asegurar que no exceda la cantidad de nodos disponibles
    nN = min(nN, length(all_nodes))
    nodos = all_nodes[1:nN]

    # Extraer coordenadas X e Y
    x_coords, y_coords = first.(nodos), last.(nodos)

    # Crear gráfico
    fig, ax = subplots()
    ax.scatter(x_coords, y_coords, s=50, c="black")  # s es el tamaño del marcador

    # Quitar ejes y cuadrícula
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_frame_on(false)

    show()
end