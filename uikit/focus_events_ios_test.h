#import <UIKit/UIKit.h>

#if __has_feature(objc_arc)
#define UI2_FOCUS_TEST_INPUT(pointer) ((__bridge id<UITextInput>)(pointer))
#else
#define UI2_FOCUS_TEST_INPUT(pointer) ((id<UITextInput>)(pointer))
#endif

static inline void ui2_ios_focus_test_select(void *pointer, long location, long length) {
    id<UITextInput> input = UI2_FOCUS_TEST_INPUT(pointer);
    UITextPosition *start = [input positionFromPosition:input.beginningOfDocument offset:location];
    UITextPosition *end = [input positionFromPosition:start offset:length];
    input.selectedTextRange = [input textRangeFromPosition:start toPosition:end];
}
static inline BOOL ui2_ios_focus_test_selection_is(void *pointer, long location, long length) {
    id<UITextInput> input = UI2_FOCUS_TEST_INPUT(pointer);
    UITextRange *selection = input.selectedTextRange;
    return selection != nil
        && [input offsetFromPosition:input.beginningOfDocument toPosition:selection.start] == location
        && [input offsetFromPosition:selection.start toPosition:selection.end] == length;
}
