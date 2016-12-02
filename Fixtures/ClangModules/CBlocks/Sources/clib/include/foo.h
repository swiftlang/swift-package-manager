typedef int (^Operation)(int, int);

int operate(int a, int b, Operation operation);
int addOperation(int a, int b);
