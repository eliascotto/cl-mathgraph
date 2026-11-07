(in-package #:mathbook)

(defvar *interface-font* nil "Owned font for the current graphics context, or NIL.")
(defvar *interface-font-path* nil "Path of the font currently loaded for the interface.")

(defun interface-font-candidates ()
  "Prefer installed Inter, then native or common sans-serif fonts."
  (remove nil
          (list (getenv "MATHBOOK_FONT")
                (merge-pathnames "Library/Fonts/InterVariable.ttf" (user-homedir-pathname))
                (merge-pathnames "Library/Fonts/Inter-Regular.ttf" (user-homedir-pathname))
                #p"/System/Library/Fonts/SFNS.ttf"
                #p"/System/Library/Fonts/Supplemental/Arial.ttf"
                #p"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
                #p"/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf"
                #+win32 #p"C:/Windows/Fonts/segoeui.ttf")))

(defun release-interface-font ()
  "Detach and unload the owned font while its window's graphics context is alive."
  (when *interface-font*
    ;; Raygui borrows this font. Detach it before unloading or resetting styles,
    ;; since GuiLoadStyleDefault itself frees any custom font still attached.
    (raygui:gui-set-font (raylib:get-font-default))
    (raylib:unload-font *interface-font*)
    (setf *interface-font* nil *interface-font-path* nil)))

(defun initialize-interface ()
  "Load a smooth sans-serif font for the current window and configure raygui."
  (release-interface-font)
  (let ((default-font (raylib:get-font-default)))
    (raygui:gui-set-font default-font)
    (raygui:gui-load-style-default)
    (dolist (path (interface-font-candidates))
      (when (probe-file path)
        ;; Rasterize at twice the 16px UI size, then filter when drawing smaller.
        (let* ((font (raylib:load-font-ex (namestring path) 32 (cffi:null-pointer) 0))
               (texture (raylib:font-texture font)))
          ;; LoadFontEx returns the default bitmap font on failure; do not own it.
          (when (and (plusp (raylib:texture-id texture))
                     (/= (raylib:texture-id texture)
                         (raylib:texture-id (raylib:font-texture default-font))))
            (setf *interface-font* font *interface-font-path* (namestring path))
            (raylib:set-texture-filter texture 1) ; TEXTURE_FILTER_BILINEAR
            (raygui:gui-set-font font)
            (return)))))
    (raygui:gui-set-style raygui:+default+ raygui:+text-size+ 16)
    (raygui:gui-set-style raygui:+default+ raygui:+text-spacing+ 0)
    (raygui:gui-set-style raygui:+textbox+ raygui:+base-color-focused+ #xffffffff)
    (raygui:gui-set-style raygui:+textbox+ raygui:+base-color-pressed+ #xffffffff)))

(defun canvas-text-width (text size)
  "Measure chart labels with the same font and spacing used to draw them."
  (if *interface-font*
      (ceiling (3d-vectors:vx
                (raylib:measure-text-ex *interface-font* text (float size 1f0) 0f0)))
      (raylib:measure-text text size)))

(defun draw-canvas-text (text x y size color)
  (if *interface-font*
      (raylib:draw-text-ex *interface-font* text (3d-vectors:vec2 x y)
                           (float size 1f0) 0f0 color)
      (raylib:draw-text text x y size color)))
