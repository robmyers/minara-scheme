/*
  minara - a programmable graphics program editor
  Copyright (C) 2004  Rob Myers rob@robmyers.org

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*/

#ifndef MINARA_WINDOW_INCLUDE
#define MINARA_WINDOW_INCLUDE

#ifdef __APPLE__
#include <OpenGL/gl.h>
#else
#include <GL/gl.h>
#endif

// Our main window structure
typedef struct MinaraWindow {
  int window;
  GLuint displayList;
  char * buffer;
  int shouldRedraw;
  struct MinaraWindow * next;
} MinaraWindow;

// The list of windows
extern MinaraWindow * gWindows;

// Default window size
extern int gScreenWidth;
extern int gScreenHeight;

void MinaraWindowInsert (MinaraWindow ** root, MinaraWindow * con);
void MinaraWindowRemove (MinaraWindow ** root, int win);
MinaraWindow * MinaraWindowGet (MinaraWindow * root, int win);
void MinaraWindowMake (MinaraWindow ** con, int width, int height, char * name);
void MinaraWindowDestroy (MinaraWindow * con);
void MinaraWindowResize (MinaraWindow * root, int win, 
			 int width, int height);
void MinaraWindowDraw (MinaraWindow * root, int win);

void WindowStartup ();

#endif