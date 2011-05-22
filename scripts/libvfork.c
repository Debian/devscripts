#include <sys/types.h>
#include <unistd.h>

#undef vfork

pid_t vfork(void){
    return fork();
}
