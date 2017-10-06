#*****************************************************************************
#* 
#*  @file          Makefile
#*
#*                 Mobile Data Connector
#*
#*  @par Program:  User mode utilities
#*
#*  @version       1.0 (\$Revision$)
#*  @author        Guido Classen
#*                 SWARCO Traffic Systems GmbH
#* 
#*  $LastChangedBy$  
#*  $Date$
#*  $URL$
#*
#*  @par Modification History:
#*   2007-02-05 gc: initial version
#*
#*  @par Makefile calls:
#*
#*  Build: 
#*   make 
#*
#*****************************************************************************

.PHONY: all
all: install


.PHONY: install
install:
	cd rootfs_overlay && cp -a . $(TARGET_DIR)/

# Local Variables:
# mode: makefile
# compile-command: "make"
# End:
