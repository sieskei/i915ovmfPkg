

// unused, can't be arsed dealing with that shitty build system to figure out how to link it.
// but maybe one day...or someone?
unsigned long __stack_chk_guard;
void __stack_chk_guard_setup(void)
{
     __stack_chk_guard = 0xFFFFFFFB;//provide some magic numbers
}

void __stack_chk_fail(void)
{
 /* Error message */                                 
}// will be called when guard variable is corrupted 
