rootPath = ../
include ../include.mk

cflags += ${tokyoCabinetIncl}

all : ${binPath}/cactus_convertAlignmentsToInternalNames ${binPath}/cactus_stripUniqueIDs ${binPath}/cactus_blast_convertCoordinates ${binPath}/cactus_blast_chunkSequences ${binPath}/cactus_blast_chunkFlowerSequences ${binPath}/cactus_blast_sortAlignments ${binPath}/cactus_coverage

${binPath}/cactus_blast_chunkFlowerSequences : *.c ${libPath}/cactusBlastAlignment.a ${libPath}/cactusLib.a ${basicLibsDependencies}
	${cxx} ${cflags} -I${libPath} -o ${binPath}/cactus_blast_chunkFlowerSequences cactus_blast_chunkFlowerSequences.c ${libPath}/cactusBlastAlignment.a ${libPath}/cactusLib.a ${basicLibs}

${binPath}/cactus_blast_chunkSequences : *.c ${libPath}/cactusBlastAlignment.a ${libPath}/cactusLib.a ${basicLibsDependencies}
	${cxx} ${cflags} -I${libPath} -o ${binPath}/cactus_blast_chunkSequences cactus_blast_chunkSequences.c ${libPath}/cactusBlastAlignment.a ${libPath}/cactusLib.a ${basicLibs}

${binPath}/cactus_blast_convertCoordinates : *.c ${libPath}/cactusBlastAlignment.a ${libPath}/cactusLib.a ${basicLibsDependencies}
	${cxx} ${cflags} -I${libPath} -o ${binPath}/cactus_blast_convertCoordinates cactus_blast_convertCoordinates.c ${libPath}/cactusBlastAlignment.a ${libPath}/cactusLib.a ${basicLibs}

${binPath}/cactus_blast_sortAlignments : cactus_blast_sortAlignments.c ${libPath}/stCaf.a ${libPath}/cactusLib.a ${basicLibsDependencies}
	${cxx} ${cflags} -I inc -I${libPath} -o ${binPath}/cactus_blast_sortAlignments cactus_blast_sortAlignments.c ${libPath}/stCaf.a ${libPath}/cactusBlastAlignment.a ${libPath}/cactusLib.a ${basicLibs}


${binPath}/cactus_coverage : cactus_coverage.c ${basicLibsDependencies}
	${cxx} ${cflags} -I inc -I${libPath} -o ${binPath}/cactus_coverage cactus_coverage.c ${basicLibs}

${binPath}/cactus_convertAlignmentsToInternalNames : cactus_convertAlignmentsToInternalNames.c ${libPath}/cactusLib.a
	${cxx} ${cflags} -I inc -I${libPath} -o ${binPath}/cactus_convertAlignmentsToInternalNames cactus_convertAlignmentsToInternalNames.c ${libPath}/cactusLib.a ${basicLibs}

${binPath}/cactus_stripUniqueIDs : cactus_stripUniqueIDs.c ${libPath}/cactusLib.a
	${cxx} ${cflags} -I inc -I${libPath} -o ${binPath}/cactus_stripUniqueIDs cactus_stripUniqueIDs.c ${libPath}/cactusLib.a ${basicLibs}

clean : 
	rm -f *.o
	rm -f ${libPath}/cactusBlastAlignment.a ${binPath}/cactus_blast.py ${binPath}/cactus_blast_chunkSequences ${binPath}/cactus_blast_sortAlignments ${binPath}/cactus_blast_chunkFlowerSequences ${binPath}/cactus_blast_convertCoordinates 
