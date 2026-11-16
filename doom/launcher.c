// QHPC DOOMATHON launcher: the program's entry point.
//
// TEAM-OWNED FILE: change it however you like.

#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

#include "doomgeneric.h"
#include "d_main.h"

int main(int argc, char **argv)
{
    // One shared, expensive load (WAD parse, texture/sound precache, lump
    // hash table): doomgeneric_Create() now runs only the truncated
    // D_DoomMain(), which stops right after ST_Init(). Everything after
    // that is per-demo state, replayed by forking a copy-on-write child
    // off this loaded image instead of exec()'ing a whole new process.
    doomgeneric_Create(argc, argv);

    for (;;)
    {
        pid_t child = fork();

        if (child < 0)
        {
            perror("fork");
            exit(1);
        }

        if (child == 0)
        {
            // Child: play exactly one demo, then exit the way the engine
            // always has (I_Error -> exit(-1) at end of demo, via
            // G_CheckDemoStatus). Never returns.
            D_DoomMain_PlayDemo();

            for (;;)
                doomgeneric_Tick();
        }

        // Parent: strictly sequential -- wait for this child before
        // forking the next one. Required, not just tidy: the WAD/demo
        // file descriptors are shared (COW) across the fork, and
        // W_StdC_Read's fseek+fread pairs are only race-free with at
        // most one reader at a time.
        int status;
        waitpid(child, &status, 0);
    }

    return 0;
}
