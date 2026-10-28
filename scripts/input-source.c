// input-source ascii        select the current ASCII-capable keyboard layout;
//                           print the previous source's ID if it changed
// input-source select ID    select the input source with ID
//
// The same Text Input Sources calls herdr uses for
// switch_ascii_input_source_in_prefix. Built by init.lua on first use:
//   clang -framework Carbon -o input-source input-source.c
#include <Carbon/Carbon.h>
#include <stdio.h>
#include <string.h>

static int print_id(TISInputSourceRef source) {
  CFStringRef id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
  char buf[256];
  if (!id || !CFStringGetCString(id, buf, sizeof buf, kCFStringEncodingUTF8)) return 1;
  printf("%s\n", buf);
  return 0;
}

int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "ascii") == 0) {
    TISInputSourceRef current = TISCopyCurrentKeyboardInputSource();
    TISInputSourceRef ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    if (!current || !ascii) return 1;
    CFStringRef a = TISGetInputSourceProperty(current, kTISPropertyInputSourceID);
    CFStringRef b = TISGetInputSourceProperty(ascii, kTISPropertyInputSourceID);
    int rc = 0;
    if (!(a && b && CFEqual(a, b))) {
      if (TISSelectInputSource(ascii) == noErr) rc = print_id(current);
      else rc = 1;
    }
    CFRelease(current);
    CFRelease(ascii);
    return rc;
  }
  if (argc == 3 && strcmp(argv[1], "select") == 0) {
    CFStringRef id = CFStringCreateWithCString(NULL, argv[2], kCFStringEncodingUTF8);
    const void *keys[] = { kTISPropertyInputSourceID };
    const void *values[] = { id };
    CFDictionaryRef filter = CFDictionaryCreate(NULL, keys, values, 1,
      &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFArrayRef list = TISCreateInputSourceList(filter, false);
    int rc = 1;
    if (list && CFArrayGetCount(list) > 0)
      rc = TISSelectInputSource((TISInputSourceRef)CFArrayGetValueAtIndex(list, 0)) == noErr ? 0 : 1;
    if (list) CFRelease(list);
    CFRelease(filter);
    CFRelease(id);
    return rc;
  }
  fprintf(stderr, "usage: input-source ascii | select ID\n");
  return 2;
}
