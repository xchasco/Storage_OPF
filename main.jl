# Load all Libraries
include("./Functions/loadLibraries.jl")

# Load all Functions
include("./Functions/loadFunctions.jl")


# First, tests are loaded for a faster solver load
boot()

# Variable for loop end
endProgramm = false
# In case that we are not into the end of the programm
while !endProgramm

    # Clean Terminal
    cleanTerminal()

    # Enter into a loop to select the study case
    case, opfType, s = selectEstudio()

    # Clean Terminal
    cleanTerminal()

    # Se extrae los datos del caso de estudio
    # Donde:
    #   datos[1] = datos de las líneas
    #   datos[2] = datos de los generadores
    #   datos[3] = datos de la demanda
    #   datos[4] = número de nodos
    #   datos[5] = número de líneas
    #   datos[6] = potencia base
    #   datos[7] = ruta al archivo .m del caso
    println("\nExtrayendo datos...")
    datos = extraerDatos(case)
    println("Datos extraídos.")

    # Una vez elegido el caso de estudio se llama a la función correspondiente para realizar el cálculo del problema de optimización
    println("\nGenerando OPF...")
    # En caso de un LP-OPF
    if opfType == "LP-OPF"
        m, solGen, solFlujos, solTension = LP_OPF(datos[1], datos[2], datos[3], datos[4], datos[5], datos[6], s)

    # En caso de un AC-OPF
    elseif opfType == "AC-OPF"
        m, solGen, solFlujos, solTension = AC_OPF(datos[1], datos[2], datos[3], datos[4], datos[5], datos[6], s)

    # Si se llega hasta este punto y no se da ningún caso anterior, devuelve un error
    else
        println("ERROR: Fallo en cargar el tipo de OPF")

    end

    # Limpieza del terminal
    cleanTerminal()

    # Gensión de los resultados de optimización
    println("Problema resuelto")
    gestorResultados(m, solGen, solFlujos, solTension, datos[7], opfType, s)

    # Preguntar al usuario si quiere continuar en el bucle para estudiar otro caso
    println("\nPulsa la tecla ENTER para continuar o cualquier otra entrada para salir.")
    if readline() == ""
        # Se mantiene la variable en falso para continuar en el bucle
        finPrograma = false
    else
        # Actualización de la variable para salir del bucle
        finPrograma = true
        exit()
    end

end