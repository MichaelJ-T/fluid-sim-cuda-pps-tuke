#include <stdio.h>
#include <stdlib.h>
#include <windows.h>
#include <conio.h>
#include <tchar.h>
#include <time.h>
#include <stdbool.h>

#define ELEM_U 0
#define ELEM_V 1
#define ELEM_DENS 2
#define ELEM_NUM 3
//#define ENGINE_STARTED 1.01
//#define FRAME_FINISHED 1.02
#define STOP_ENGINE 1.0
#define NEXT_FRAME 2.0
#define NO_MESSAGE 0.0
//#define FRAME_DISPLAYED 0.02
/*#define swap(fp1, fp2)    \
    {                     \
        float *tmp = fp1; \
        fp1 = fp2;        \
        fp1 = tmp;        \
    }*/
#define IDX(c, r, e) (((c) + (size + 2) * (r)) * ELEM_NUM + (e))

__device__ void set_bnd(int size, int b, float *matrix, int elem)
{
    int i;
    for (i = 1; i <= size; i++)
    {
        matrix[IDX(0, i, elem)] = b == 1 ? -matrix[IDX(1, i, elem)] : matrix[IDX(1, i, elem)];
        matrix[IDX(size + 1, i, elem)] = b == 1 ? -matrix[IDX(size, i, elem)] : matrix[IDX(size, i, elem)];
        matrix[IDX(i, 0, elem)] = b == 2 ? -matrix[IDX(i, 1, elem)] : matrix[IDX(i, 1, elem)];
        matrix[IDX(i, size + 1, elem)] = b == 2 ? -matrix[IDX(i, size, elem)] : matrix[IDX(i, size, elem)];
    }
    matrix[IDX(0, 0, elem)] = 0.5 * (matrix[IDX(1, 0, elem)] + matrix[IDX(0, 1, elem)]);
    matrix[IDX(0, size + 1, elem)] = 0.5 * (matrix[IDX(1, size + 1, elem)] + matrix[IDX(0, size, elem)]);
    matrix[IDX(size + 1, 0, elem)] = 0.5 * (matrix[IDX(size, 0, elem)] + matrix[IDX(size + 1, 1, elem)]);
    matrix[IDX(size + 1, size + 1, elem)] = 0.5 * (matrix[IDX(size, size + 1, elem)] + matrix[IDX(size + 1, size, elem)]);
}

__global__ void diffuse(int size, int idxOfElem, int b, float *state, float *state_prev, float diff, float dt, int num_of_indeces_block, int num_of_indeces_thread)
{
    int start_idx = num_of_indeces_block * blockIdx.x + num_of_indeces_thread * threadIdx.x;
    int end_idx = ((start_idx + num_of_indeces_thread) <= size) ? start_idx + num_of_indeces_thread : 0;
    if (end_idx == size)
        end_idx++;
    if (start_idx == 0)
        start_idx++;
    int row, col, k;
    float a = dt * diff * size * size;
    for (k = 0; k < 20; k++)
    {
        for (col = 1; col <= size; col++)
        {
            for (row = start_idx; row < end_idx; row++)
            {
                state[IDX(col, row, idxOfElem)] =
                    (state_prev[IDX(col, row, idxOfElem)] + a * (state[IDX(col - 1, row, idxOfElem)] +
                                                                 state[IDX(col + 1, row, idxOfElem)] +
                                                                 state[IDX(col, row - 1, idxOfElem)] +
                                                                 state[IDX(col, row + 1, idxOfElem)])) /
                    (1 + 4 * a);
            }
            __syncthreads();
        }
        __syncthreads();
        set_bnd(size, b, state, idxOfElem);
    }
}
__global__ void advect(int size, int idxOfEl_d, int b, float *state, float *state_prev, float *matrix_uv, float dt, int num_of_indeces_block, int num_of_indeces_thread)
{
    int start_idx = num_of_indeces_block * blockIdx.x + num_of_indeces_thread * threadIdx.x;
    int end_idx = ((start_idx + num_of_indeces_thread) <= size) ? start_idx + num_of_indeces_thread : 0;
    if (end_idx == size)
        end_idx++;
    if (start_idx == 0)
        start_idx++;
    int i0, j0, i1, j1;
    int row, col;
    float x, y, s0, t0, s1, t1, dt0;
    dt0 = dt * size;
    for (col = 1; col <= size; col++)
    {
        for (row = start_idx; row < end_idx; row++)
        {
            // calculating particle position based on u and v elems at time dt0
            x = col - dt0 * matrix_uv[IDX(col, row, ELEM_U)];
            y = row - dt0 * matrix_uv[IDX(col, row, ELEM_V)];
            if (x < 0.5) // Checking if particle X position isnt outside of grid
                x = 0.5; // Placing particle to grid border tile center
            if (x > size + 0.5)
                x = size + 0.5;
            i0 = (int)x; // Previous tile X position is same as centered particle X
            i1 = i0 + 1; // Current tile X
            if (y < 0.5)
                y = 0.5;
            if (y > size + 0.5)
                y = size + 0.5;
            j0 = (int)y;
            j1 = j0 + 1;
            s1 = x - i0;
            s0 = 1 - s1;
            t1 = y - j0;
            t0 = 1 - t1;
            state[IDX(col, row, idxOfEl_d)] =
                s0 * (t0 * state_prev[IDX(i0, j0, idxOfEl_d)] + t1 * state_prev[IDX(i0, j1, idxOfEl_d)]) +
                s1 * (t0 * state_prev[IDX(i1, j0, idxOfEl_d)] + t1 * state_prev[IDX(i1, j1, idxOfEl_d)]);
        }
        __syncthreads();
    }
    set_bnd(size, b, state, idxOfEl_d);
}

__global__ void project(int size, float *state, float *state_prev)
{
    if (blockIdx.x == 0 && threadIdx.x == 0)
    {
        int row, col, k;
        float h;
        h = 1.0 / size;
        for (col = 1; col <= size; col++)
        {
            for (row = 1; row <= size; row++)
            {
                state_prev[IDX(col, row, ELEM_V)] =
                    -0.5 * h *
                    (state[IDX(col + 1, row, ELEM_U)] - state[IDX(col - 1, row, ELEM_U)] +
                     state[IDX(col, row + 1, ELEM_V)] - state[IDX(col, row - 1, ELEM_V)]);
                state_prev[IDX(col, row, ELEM_U)] = 0;
            }
        }
        set_bnd(size, 0, state_prev, ELEM_V);
        set_bnd(size, 0, state_prev, ELEM_U);

        for (k = 0; k < 20; k++)
        {
            for (col = 1; col <= size; col++)
            {
                for (row = 1; row <= size; row++)
                {
                    state_prev[IDX(col, row, ELEM_U)] =
                        (state_prev[IDX(col, row, ELEM_V)] +
                         state_prev[IDX(col - 1, row, ELEM_U)] + state_prev[IDX(col + 1, row, ELEM_U)] +
                         state_prev[IDX(col, row - 1, ELEM_U)] + state_prev[IDX(col, row + 1, ELEM_U)]) /
                        4;
                }
            }

            set_bnd(size, 0, state_prev, ELEM_U);
        }
        for (col = 1; col <= size; col++)
        {
            for (row = 1; row <= size; row++)
            {
                state[IDX(col, row, ELEM_U)] -=
                    0.5 * (state_prev[IDX(col + 1, row, ELEM_U)] - state_prev[IDX(col - 1, row, ELEM_U)]) / h;
                state[IDX(col, row, ELEM_V)] -=
                    0.5 * (state_prev[IDX(col, row + 1, ELEM_U)] - state_prev[IDX(col, row - 1, ELEM_U)]) / h;
            }
        }
        set_bnd(size, 1, state, ELEM_U);
        set_bnd(size, 2, state, ELEM_V);
    }
}

void swap(float *&a, float *&b)
{
    float *temp = a;
    a = b;
    b = temp;
}

int getItemFormArgInt(int argc, char *argv[], char a, int defaultV);
float getItemFormArgFloat(int argc, char *argv[], char a, float defaultV);
float Str2float10b(char str[]);

TCHAR szName[] = TEXT("sharedMemForFluidSim"); // Global

int main(int argc, char *argv[])
{
    int framesCreated = 1;
    double time_spend_avg_diff = 0;
    double time_spend_avg_vel = 0;
    int size = 0;
    size = getItemFormArgInt(argc, argv, 's', -1);
    if (size < 0)
    {
        printf("Size was never found in arguments,\n or there was an error during conversion\n");
        exit(-1);
    }
    int full_size = (size + 2) * (size + 2);
    const int comm_channels = 2;
    const int size_w_elem = full_size * ELEM_NUM;                   // Size of grid with spaces between tiles
    const int in_commands = size_w_elem;                            // Index where command from ui are located
    float diff_rate = getItemFormArgFloat(argc, argv, 'd', 0.001f); // diffusion rate
    float dt = getItemFormArgFloat(argc, argv, 'w', 0.001f);        // Time spacing between frames (snapshots)
    float *state;                                                   // Includes u, v, density
    float *state_prev;                                              // Includes u, v, density
    int blocks = getItemFormArgInt(argc, argv, 'b', 1);
    int threads = getItemFormArgInt(argc, argv, 't', 1);
    int mul_blocks_threads = (blocks * threads <= 0) ? 1 : blocks * threads;
    int num_of_indeces_thread = (int)ceil((float)(size) / (float)mul_blocks_threads);
    int num_of_indeces_block = num_of_indeces_thread * threads;
    num_of_indeces_block = (num_of_indeces_block == 0) ? 1 : num_of_indeces_block;
    const unsigned int sharedMemArrSize = size_w_elem + comm_channels;
    cudaMallocManaged(&state, sharedMemArrSize * sizeof(float));
    cudaMallocManaged(&state_prev, sharedMemArrSize * sizeof(float));

    state[IDX(size / 2, size / 2, ELEM_DENS)] = 1.0f;

    printf("{\"sharedMemSizeMB\":%.2f,", (float)(sharedMemArrSize * sizeof(float)) / (float)1000000);
    printf("\"sharedMemSizeB\":%d,", (int)(sharedMemArrSize * sizeof(float)));
    printf("\"n\":%d,\"blocks\":%d,\"threads\":%d,\"diffRate\":%f,\"dt\":%f,", size, blocks, threads, diff_rate, dt);
    printf("\"buffLen\":%u,", sharedMemArrSize);
    HANDLE hMapFile;
    LPCTSTR pBuf;

    /*Creates file mapping object in memory and saves the handle to hMapFile*/
    hMapFile = OpenFileMapping(
        FILE_MAP_ALL_ACCESS, // read/write access
        FALSE,               // do not inherit the name
        szName);             // name of mapping object

    if (hMapFile == NULL)
    {
        _tprintf(TEXT("Could not open file mapping object (%d).\n"),
                 GetLastError());
        return 1;
    }
    /*tries to connect mapping object to memory of this process*/
    pBuf = (LPTSTR)MapViewOfFile(hMapFile,            // handle to map object
                                 FILE_MAP_ALL_ACCESS, // read/write permission
                                 0,
                                 0,
                                 (int)(size_w_elem * sizeof(float)));
    /*Checks if connection attempt was successful*/
    if (pBuf == NULL)
    {
        _tprintf(TEXT("Could not map view of file (%d).\n"),
                 GetLastError());

        CloseHandle(hMapFile);

        return 1;
    }

    bool run = true;
    clock_t begin_of_mesurement = clock();
    clock_t end_of_mesurement = clock();
    while (run)
    {
        // getchar();
        while (state[in_commands] == NO_MESSAGE)
        {
            cudaMemcpy(state, pBuf, (int)(sharedMemArrSize * sizeof(float)), cudaMemcpyHostToDevice);
            if (state[in_commands] == STOP_ENGINE)
                run = false;
            if (state[in_commands] == NEXT_FRAME)
            {
                state[in_commands] = NO_MESSAGE;
                cudaMemcpy((PVOID)pBuf, state, (int)(sharedMemArrSize * sizeof(float)), cudaMemcpyDeviceToHost);
                break;
            }
            // printf("%f - %f\n", state[in_commands], STOP_ENGINE);
            Sleep(10);
        }
        // Velocity steps
        begin_of_mesurement = clock();
        swap(state, state_prev);
        diffuse<<<blocks, threads>>>(size, ELEM_U, 1, state, state_prev, diff_rate, dt, num_of_indeces_block, num_of_indeces_thread);
        diffuse<<<blocks, threads>>>(size, ELEM_V, 2, state, state_prev, diff_rate, dt, num_of_indeces_block, num_of_indeces_thread);
        cudaDeviceSynchronize();
        project<<<blocks, threads>>>(size, state, state_prev);
        cudaDeviceSynchronize();
        swap(state, state_prev);
        advect<<<blocks, threads>>>(size, ELEM_U, 1, state, state_prev, state_prev, diff_rate, num_of_indeces_block, num_of_indeces_thread);
        cudaDeviceSynchronize();
        advect<<<blocks, threads>>>(size, ELEM_V, 2, state, state_prev, state_prev, diff_rate, num_of_indeces_block, num_of_indeces_thread);
        cudaDeviceSynchronize();
        project<<<blocks, threads>>>(size, state, state_prev);
        cudaDeviceSynchronize();
        end_of_mesurement = clock();
        time_spend_avg_vel += (double)(end_of_mesurement - begin_of_mesurement) * 1000000.0 / CLOCKS_PER_SEC;
        // Density steps
        begin_of_mesurement = clock();
        swap(state, state_prev);                                                                                                         // Swaping current state to previous
        diffuse<<<blocks, threads>>>(size, ELEM_DENS, 0, state, state_prev, diff_rate, dt, num_of_indeces_block, num_of_indeces_thread); // Calculate diffusion
        cudaDeviceSynchronize();
        swap(state, state_prev);                                                                                                           // Swaping current state to previous
        advect<<<blocks, threads>>>(size, ELEM_DENS, 0, state, state_prev, state, diff_rate, num_of_indeces_block, num_of_indeces_thread); // Moving density
        cudaDeviceSynchronize();
        end_of_mesurement = clock();

        time_spend_avg_diff += (double)(end_of_mesurement - begin_of_mesurement) * 1000000.0 / CLOCKS_PER_SEC;

        cudaMemcpy((PVOID)pBuf, state, (int)(size_w_elem * sizeof(float)), cudaMemcpyDeviceToHost);
        //  printf("%d - %s\n %s\n ---\n", cudaGetLastError(), cudaGetErrorName(cudaGetLastError()), cudaGetErrorString(cudaGetLastError()));
        framesCreated++;
    }

    UnmapViewOfFile(pBuf);
    CloseHandle(hMapFile);

    // Free memory
    cudaFree(state);
    cudaFree(state_prev);

    time_spend_avg_diff /= framesCreated;
    int sec = time_spend_avg_diff / 1000000;
    time_spend_avg_diff = time_spend_avg_diff - 1000000 * sec;
    int ms = time_spend_avg_diff / 1000;
    time_spend_avg_diff = time_spend_avg_diff - 1000 * ms;
    printf("\"diffusion\":[\"%d\",\"%d\",\"%03d\"],", sec, ms, (int)time_spend_avg_diff);
    time_spend_avg_vel /= framesCreated;
    sec = time_spend_avg_vel / 1000000;
    time_spend_avg_vel = time_spend_avg_vel - 1000000 * sec;
    ms = time_spend_avg_vel / 1000;
    time_spend_avg_vel = time_spend_avg_vel - 1000 * ms;
    printf("\"velocity\":[\"%d\",\"%d\",\"%03d\"],", sec, ms, (int)time_spend_avg_vel);
    printf("\"frames\":%d}", framesCreated);
    return 0;
}

int getItemFormArgInt(int argc, char *argv[], char a = 's', int defaultV = -1)
{
    int i;
    int numberOf = 0;
    int found = false;
    for (i = 0; i < argc; i++)
    {
        if (strlen(argv[i]) > 3 && argv[i][0] == '-' && argv[i][1] == a && argv[i][2] == '=')
        {
            found = true;
            break;
        }
    }
    if (!found)
        return defaultV;
    char *token;
    const char s[2] = "=";
    // printf("%s\n", argv[i]);
    token = strtok(argv[i], s);
    while (token != NULL)
    {
        int converted = strtol(token, (char **)NULL, 10);
        if (converted > 0)
        {
            numberOf = converted;
            return numberOf;
        }
        token = strtok(NULL, s);
    }
    return (numberOf > 0) ? numberOf : defaultV;
}
float getItemFormArgFloat(int argc, char *argv[], char a = 's', float defaultV = 0.01)
{
    int i;
    float numberOf = 0;
    int found = false;
    for (i = 0; i < argc; i++)
    {
        if (strlen(argv[i]) > 3 && argv[i][0] == '-' && argv[i][1] == a && argv[i][2] == '=')
        {
            found = true;
            break;
        }
    }
    if (!found)
        return defaultV;
    char *token;
    const char s[2] = "=";
    // printf("%s\n", argv[i]);
    token = strtok(argv[i], s);
    while (token != NULL)
    {
        float converted = Str2float10b(token);
        if (converted > 0)
        {
            numberOf = converted;
            return numberOf;
        }
        token = strtok(NULL, s);
    }
    return (numberOf > 0) ? numberOf : defaultV;
}

float Str2float10b(char str[])
{
    int str_size = strlen(str);
    int floating_point_idx = 0;
    char *float_p;
    float_p = strchr(str, '.');
    floating_point_idx = (int)(float_p - str);

    char before_fp[50];
    char after_fp[50];

    int before_idx = 0;
    int after_idx = 0;
    for (int str_idx = 0; str_idx < str_size; str_idx++)
    {
        if (str_idx < floating_point_idx)
        {
            before_fp[before_idx] = str[str_idx];
            before_idx++;
            before_fp[before_idx] = '\0';
        }
        else if (str_idx > floating_point_idx)
        {
            after_fp[after_idx] = str[str_idx];
            after_idx++;
            after_fp[after_idx] = '\0';
        }
    }

    float result = (float)strtol(before_fp, (char **)NULL, 10);
    float decimal = (float)strtol(after_fp, (char **)NULL, 10) / pow(10, strlen(after_fp));
    result += (str[0] == '-') ? -decimal : decimal;
    return result;
}