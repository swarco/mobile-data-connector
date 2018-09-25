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

CRONTAB_ENTRY = "\# m h dom mon dow command\n\# gprs-connection-test.sh runs ntp-query.sh twice a day when NTP-servers are configured\n24 2,14  * * * /etc/ppp/gprs-connection-test.sh"

.PHONY: install
install:
	cd rootfs_overlay && cp -a . $(TARGET_DIR)/
	grep gprs-connection-test.sh <$(TARGET_DIR)/etc/crontab >/dev/null 2>&1 || echo $(CRONTAB_ENTRY) >>$(TARGET_DIR)/etc/crontab 


# Local Variables:
# mode: makefile
# compile-command: "make"
# End:
