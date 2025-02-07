#import <CLibrary.h>

int main(int argc, const char* argv[]) {
	printf("%s", [CLibrary new].description.UTF8String);
}
