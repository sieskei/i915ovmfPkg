#include "i915_gop.h"
STATIC EFI_GRAPHICS_OUTPUT_MODE_INFORMATION g_mode_info[] = {
  {
    0,    // Version
    1024,  // HorizontalResolution
    768,  // VerticalResolution
  }
};

STATIC EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE g_mode = {
  ARRAY_SIZE (g_mode_info),                // MaxMode
  0,                                              // Mode
  g_mode_info,                             // Info
  sizeof (EFI_GRAPHICS_OUTPUT_MODE_INFORMATION),  // SizeOfInfo
};
STATIC EFI_STATUS EFIAPI i915GraphicsOutputQueryMode (
  IN  EFI_GRAPHICS_OUTPUT_PROTOCOL          *This,
  IN  UINT32                                ModeNumber,
  OUT UINTN                                 *SizeOfInfo,
  OUT EFI_GRAPHICS_OUTPUT_MODE_INFORMATION  **Info
  )
{
  EFI_GRAPHICS_OUTPUT_MODE_INFORMATION  *ModeInfo;
  DebugPrint(EFI_D_ERROR,"i915: query mode\n");

  if (Info == NULL || SizeOfInfo == NULL ||
      ModeNumber >= g_mode.MaxMode) {
    return EFI_INVALID_PARAMETER;
  }
  ModeInfo = &g_mode_info[ModeNumber];

  *Info = AllocateCopyPool (sizeof (EFI_GRAPHICS_OUTPUT_MODE_INFORMATION), ModeInfo);
  if (*Info == NULL) {
    return EFI_OUT_OF_RESOURCES;
  }
  *SizeOfInfo = sizeof (EFI_GRAPHICS_OUTPUT_MODE_INFORMATION);

  return EFI_SUCCESS;
}

STATIC FRAME_BUFFER_CONFIGURE        *g_i915FrameBufferBltConfigure=NULL;
STATIC UINTN                         g_i915FrameBufferBltConfigureSize=0;
STATIC INTN g_already_set=0;
EFI_STATUS i915GraphicsFramebufferConfigure(i915_CONTROLLER* controller, UINTN fbSize) {
    g_mode.FrameBufferBase=controller->FbBase;
	g_mode.FrameBufferSize=fbSize;
		
	// //test pattern
	// //there is just one page wrapping around... why?
	// //we have intel_vgpu_mmap in effect so the correct range is mmaped host vmem
	// //and the host vmem is actually one-page!
	// ((UINT32*)controller->FbBase)[-1]=0x00010203;
	// //there is a mechanism called `get_pages` that seems to put main memory behind the aperture or sth
	// //the page is the scratch page that unmapped GTT entries point to
	// //we need to set up a GTT for our framebuffer: https://bwidawsk.net/blog/index.php/2014/06/the-global-gtt-part-1/
	// UINT32 cnt=0;
	// for(cnt=0;cnt<256*16;cnt++){
	// 	((UINT32*)controller->FbBase)[cnt]=0x00010203;
	// }
	// for(cnt=0;cnt<256*4;cnt++){
	// 	UINT32 c=cnt&255;
	// 	((UINT32*)controller->FbBase)[cnt]=((cnt+256)&256?c:0)+((cnt+256)&512?c<<8:0)+((cnt+256)&1024?c<<16:0);
	// }
	// DebugPrint(EFI_D_ERROR,"i915: wrap test %08x %08x %08x %08x\n",((UINT32*)controller->FbBase)[1024],((UINT32*)controller->FbBase)[1025],((UINT32*)controller->FbBase)[1026],((UINT32*)controller->FbBase)[1027]);
	// //
	// cnt=0;
	// for(UINT32 y=0;y<vertical_active;y+=1){
	// 	for(UINT32 x=0;x<horizontal_active;x+=1){
	// 		UINT32 data=(((x<<8)/horizontal_active)<<16)|(((y<<8)/vertical_active)<<8);
	// 		((UINT32*)controller->FbBase)[cnt]=(data&0xffff00)|0x80;
	// 		cnt++;
	// 	}
	// }
	// write32(_DSPACNTR,DISPLAY_PLANE_ENABLE|DISPPLANE_BGRX888);

	
	//blt stuff
	EFI_STATUS Status;
	Status = FrameBufferBltConfigure (
	           (VOID*)controller->FbBase,
	           g_mode_info,
	           g_i915FrameBufferBltConfigure,
	           &g_i915FrameBufferBltConfigureSize
	           );

	if (Status == RETURN_BUFFER_TOO_SMALL) {
	  if (g_i915FrameBufferBltConfigure != NULL) {
	    FreePool (g_i915FrameBufferBltConfigure);
	  }
	  g_i915FrameBufferBltConfigure = AllocatePool (g_i915FrameBufferBltConfigureSize);
	  if (g_i915FrameBufferBltConfigure == NULL) {
	    g_i915FrameBufferBltConfigureSize = 0;
	    return EFI_OUT_OF_RESOURCES;
	  }

	  Status = FrameBufferBltConfigure (
	             (VOID*)controller->FbBase,
	             g_mode_info,
	             g_i915FrameBufferBltConfigure,
	             &g_i915FrameBufferBltConfigureSize
	             );
	}
	if( EFI_ERROR(Status) ){
		DebugPrint(EFI_D_ERROR,"i915: failed to setup blt\n");
	}
    return EFI_SUCCESS;
}
STATIC EFI_STATUS EFIAPI i915GraphicsOutputBlt (
  IN  EFI_GRAPHICS_OUTPUT_PROTOCOL          *This,
  IN  EFI_GRAPHICS_OUTPUT_BLT_PIXEL         *BltBuffer, OPTIONAL
  IN  EFI_GRAPHICS_OUTPUT_BLT_OPERATION     BltOperation,
  IN  UINTN                                 SourceX,
  IN  UINTN                                 SourceY,
  IN  UINTN                                 DestinationX,
  IN  UINTN                                 DestinationY,
  IN  UINTN                                 Width,
  IN  UINTN                                 Height,
  IN  UINTN                                 Delta
  )
{
	EFI_STATUS Status=FrameBufferBlt (
	         g_i915FrameBufferBltConfigure,
	         BltBuffer,
	         BltOperation,
	         SourceX,
	         SourceY,
	         DestinationX,
	         DestinationY,
	         Width,
	         Height,
	         Delta
	         );
	DebugPrint(EFI_D_ERROR,"i915: blt %d %d,%d %dx%d\n",Status,DestinationX,DestinationY,Width,Height);
	return Status;
}