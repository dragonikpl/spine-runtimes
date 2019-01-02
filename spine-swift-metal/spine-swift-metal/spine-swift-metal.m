//
//  SpineSpriteKit.m
//
//  Created by Lukasz Domaradzki on 12/11/2018.
//  Copyright © 2018 Lukasz Domaradzki. All rights reserved.
//

#import <SpineC-umbrella.h>
#import <MetalKit/MetalKit.h>
#import <Metal/Metal.h>

void _spAtlasPage_createTexture (spAtlasPage* self, const char* path) {
    NSURL *url = [NSURL fileURLWithPath:@(path)];
    MTKTextureLoader *loader = [[MTKTextureLoader alloc] initWithDevice:MTLCreateSystemDefaultDevice()];
    id<MTLTexture> texture = [loader newTextureWithContentsOfURL:url options:nil error:nil];
    self->rendererObject = path;
    self->width = (int)texture.width;
    self->height = (int)texture.height;
}

void _spAtlasPage_disposeTexture (spAtlasPage* self) {
    self->rendererObject = NULL;
}

char* _spUtil_readFile (const char* path, int* length) {
    return _spReadFile(path, length);
}
