
--Immediate Mode GUI toolkit.
--Written by Cosmin Apreutesei. Public Domain.

--Using this library requires integrating it with two APIs: a windowing
--API to hook in mouse, keyboard and repaint events, and a graphics API
--to draw widgets on. The windowing API must create an imgui object with
--imgui:new() for each window that it creates and must implement all
--self:_backend*() calls on that object for that window. Then it must call
--imgui:_render_frame(graphics_api) on the window's repaint event passing in
--the graphics API set up to draw on that window's client area. The graphics
--API needs to implement all self.cr:*() calls which map to the cairo API.
--Look at imgui_nw_cairo.lua for an example of a complete integration.

if not ... then require'imgui_demo'; return end

local ffi = require'ffi' --TODO: remove this
local box2d = require'box2d'
local color = require'color'
local glue = require'glue'

local imgui = {
	continuous_rendering = true,
	show_magnifier = true,
	tripleclicks = false,
}

--ever-growing vararg stacks -------------------------------------------------

--an ever-growing stack doesn't set its slots to nil on remove to prevent
--garbage-collecting the slots. on top of that, a vararg stack allows adding
--and removing vararg elements without creating additional tables.

local function top(t)
	return t[t.n]
end

local function push(t, v)
	local n = t.n or 0
	t[n + 1] = v
	t.n = n + 1
end

local function pop(t)
	local n = t.n
	if n == 0 then return end
	local v = t[n]
	t[n] = false
	t.n = n - 1
	return v
end

local function popn(t, n)
	local len = t.n
	n = math.min(n, len)
	for i=1,n do
		t[len-i+1] = false
	end
	t.n = len - n
end

local function topvar(t)
	local n = top(t)
	if not n then return end
	return unpack(t, t.n - n, t.n - 1)
end

local function pushvar(t, ...)
	local n = select('#', ...)
	for i=1,n do
		local v = select(i, ...)
		push(t, v)
	end
	push(t, n)
end

local function popvar(t)
	popn(t, pop(t))
end

--themed graphics ------------------------------------------------------------

imgui.themes = {}

imgui.default = {} --theme defaults, declared inline

imgui.themes.dark = glue.inherit({
	window_bg     = '#000000',
	faint_bg      = '#ffffff33',
	normal_bg     = '#ffffff4c',
	normal_fg     = '#ffffff',
	default_bg    = '#ffffff8c',
	default_fg    = '#ffffff',
	normal_border = '#ffffff66',
	hot_bg        = '#ffffff99',
 	hot_fg        = '#000000',
	selected_bg   = '#ffffff',
	selected_fg   = '#000000',
	disabled_bg   = '#ffffff4c',
	disabled_fg   = '#999999',
	error_bg      = '#ff0000b2',
	error_fg      = '#ffffff',
}, imgui.default)

imgui.themes.light = glue.inherit({
	window_bg     = '#ffffff',
	faint_bg      = '#00000033',
	normal_bg     = '#0000004c',
	normal_fg     = '#000000',
	default_bg    = '#0000008c',
	default_fg    = '#000000',
	normal_border = '#00000066',
	hot_bg        = '#00000099',
	hot_fg        = '#ffffff',
	selected_bg   = '#000000e5',
	selected_fg   = '#ffffff',
	disabled_bg   = '#0000004c',
	disabled_fg   = '#666666',
	error_bg      = '#ff0000b2',
	error_fg      = '#ffffff',
}, imgui.default)

imgui.default_theme = imgui.themes.dark

--themed color setting

local function parse_color(c, g, b, a)
	if type(c) == 'string' then
		return color.string_to_rgba(c)
	elseif type(c) == 'table' then
		local r, g, b, a = unpack(c)
		return r, g, b, a or 1
	else
		return c, g, b, a or 1
	end
end

function imgui:setcolor(color, g, b, a)
	self.cr:rgba(parse_color(self.theme[color] or color, g, b, a))
end

--themed font setting

local function str(s)
	if not s then return end
	s = glue.trim(s)
	return s ~= '' and s or nil
end
local function parse_font(font, default_font)
	local name, size, weight, slant =
		font:match'([^,]*),?([^,]*),?([^,]*),?([^,]*)'
	local t = {}
	t.name = assert(str(name) or default_font:match'^(.-),')
	t.size = tonumber(str(size)) or default_font:match',(.*)$'
	t.weight = str(weight) or 'normal'
	t.slant = str(slant) or 'normal'
	return t
end

local fonts = setmetatable({}, {__mode = 'kv'})

local function load_font(font, default_font)
	font = font or default_font
	local t = fonts[font]
	if not t then
		if type(font) == 'string' then
			t = parse_font(font, default_font)
		elseif type(font) == 'number' then
			t = parse_font(default_font, default_font)
			t.size = font
		end
		fonts[font] = t
	end
	return t
end

imgui.default.default_font = 'Open Sans,14'

function imgui:setfont(font)
	font = load_font(self.theme[font] or font, self.theme.default_font)
	self:_backend_load_font(font.name, font.weight, font.slant)
	self.cr:font_size(font.size)
	font.extents = font.extents or self.cr:font_extents()
	return font
end

--themed fill & stroke

function imgui:fill(color)
	self:setcolor(color or 'normal_bg')
	self.cr:fill()
end

function imgui:stroke(color, line_width)
	self:setcolor(color or 'normal_fg')
	self.cr:line_width(line_width or 1)
	self.cr:stroke()
end

function imgui:fillstroke(fill_color, stroke_color, line_width)
	if fill_color and stroke_color then
		self:setcolor(fill_color)
		self.cr:fill_preserve()
		self:stroke(stroke_color, line_width)
	elseif fill_color then
		self:fill(fill_color)
	elseif stroke_color then
		self:stroke(stroke_color, line_width)
	else
		self:fill()
	end
end

--themed basic shapes

function imgui:rect(x, y, w, h, ...)
	self.cr:rectangle(x, y, w, h)
	self:fillstroke(...)
end

function imgui:dot(x, y, r, ...)
	self:rect(x-r, y-r, 2*r, 2*r, ...)
end

function imgui:circle(x, y, r, ...)
	self.cr:circle(x, y, r)
	self:fillstroke(...)
end

function imgui:line(x1, y1, x2, y2, ...)
	self.cr:move_to(x1, y1)
	self.cr:line_to(x2, y2)
	self:stroke(...)
end

function imgui:curve(x1, y1, x2, y2, x3, y3, x4, y4, ...)
	self.cr:move_to(x1, y1)
	self.cr:curve_to(x2, y2, x3, y3, x4, y4)
	self:stroke(...)
end

--themed multi-line self-aligned text

local function round(x)
	return math.floor(x + 0.5)
end

local function text_args(self, s, font, color, line_spacing)
	s = tostring(s)
	font = self:setfont(font)
	self:setcolor(color or 'normal_fg')
	local line_h = font.extents.height * (line_spacing or 1)
	return s, font, line_h
end

function imgui:text_extents(s, font, line_h)
	font = self:setfont(font)
	local w, h = 0, 0
	for s in glue.lines(s) do
		local ext = cr:text_extents(s)
		w = math.max(w, ext.width)
		h = h + ext.y_bearing
	end
	return w, h
end

local function draw_text(cr, x, y, s, align, line_h) --multi-line text
	for s in glue.lines(s) do
		if align == 'right' then
			local extents = cr:text_extents(s)
			cr:move_to(x - extents.width, y)
		elseif align == 'center' then
			local extents = cr:text_extents(s)
			cr:move_to(x - round(extents.width / 2), y)
		else
			cr:move_to(x, y)
		end
		cr:show_text(s)
		y = y + line_h
	end
end

function imgui:text(x, y, s, font, color, align, line_spacing)
	local s, font, line_h = text_args(self, s, font, color, line_spacing)
	draw_text(self.cr, x, y, s, align, line_h)
end

function imgui:textbox(x, y, w, h, s, font, color, halign, valign, line_spacing)
	local s, font, line_h = text_args(self, s, font, color, line_spacing)

	self.cr:save()
	self.cr:rectangle(x, y, w, h)
	self.cr:clip()

	if halign == 'right' then
		x = x + w
	elseif halign == 'center' then
		x = x + round(w / 2)
	end

	if valign == 'top' then
		y = y + font.extents.ascent
	else
		local lines_h = 0
		for _ in lines(s) do
			lines_h = lines_h + line_h
		end
		lines_h = lines_h - line_h

		if valign == 'bottom' then
			y = y + h - font.extents.descent
		elseif valign == 'center' then
			y = y + half(h + font.extents.ascent - font.extents.descent + lines_h)
		end
		y = y - lines_h
	end

	draw_text(self.cr, x, y, s, halign, line_h)

	self.cr:restore()
end

--layouting ------------------------------------------------------------------

local function percent(s, from)
	if not (type(s) == 'string' and s:find'%%$') then return end
	local p = tonumber((s:gsub('%%$', '')))
	return p and p / 100 * (from or 1)
end

imgui.default.spacing_x = 5
imgui.default.spacing_y = 5

function imgui:_init_frame_layout()
	self._cw = self.cw
	self._ch = self.ch
	self.window_stack = {}
	self.bbox_stack = {}
	self.flow = 'h'
	self.halign = 'l'
	self.valign = 't'
	self.cr:translate(self.theme.spacing_x, self.theme.spacing_y)
	self.cw = self.cw - 2 * self.theme.spacing_x
	self.ch = self.ch - 2 * self.theme.spacing_y
end

function imgui:content_box(w, h)
	local full_w = self.cw
	local full_h = self.ch
	w = percent(w, full_w) or tonumber(w or full_w)
	h = percent(h, full_h) or tonumber(h or full_h)
	local x, y
	if self.halign == 'l' then
		x = 0
	elseif self.halign == 'r' then
		x = full_w - w
	elseif self.halign == 'c' then
		x = (full_w - w) / 2
	end
	if self.valign == 't' then
		y = 0
	elseif self.valign == 'b' then
		y = full_h - h
	elseif self.valign == 'c' then
		y = (full_h - h) / 2
	end
	return x, y, w, h
end

function imgui:begin_content_box(flow, halign, valign)
	push(self.bbox_stack, {
		flow = self.flow,
		halign = self.halign,
		valign = self.valign,
		matrix = self.cr:matrix(),
	})
	if flow then self.flow = flow end
	if halign then self.halign = halign end
	if valign then self.valign = valign end
end

function imgui:end_content_box()
	local t = pop(self.bbox_stack)
	self.flow = t.flow
	self.halign = t.halign
	self.valign = t.valign
	self.cr:matrix(t.matrix)
	self:add_content_box(t.bx, t.by, t.bw, t.bh)
end

function imgui:add_content_box(x, y, w, h)

	--update the bounding box
	local t = top(self.bbox_stack)
	if t then
		if t.bx then
			t.bx, t.by, t.bw, t.bh =
				box2d.bounding_box(t.bx, t.by, t.bw, t.bh, x, y, w, h)
		else
			t.bx, t.by, t.bw, t.bh = x, y, w, h
		end
	end

	--update client rectangle
	if self.flow == 'v' then
		local bh = h + self.theme.spacing_y
		self.ch = math.max(0, self.ch - bh)
		if self.valign ~= 'b' then
			self.cr:translate(0, h + self.theme.spacing_y)
		end
	elseif self.flow == 'h' then
		local bw = w + self.theme.spacing_x
		self.cw = math.max(0, self.cw - bw)
		if self.halign ~= 'r' then
			self.cr:translate(w + self.theme.spacing_x, 0)
		end
	end

end

function imgui:spacer(w, h)
	local x, y, w, h = self:content_box(w, h)
	self:add_content_box(x, y, w, h)
end

function imgui:box(w, h)
	local x, y, w, h = self:content_box(w, h)

	local cr = self.cr
	cr:rgb(1, .5, .5)
	cr:line_width(1)
	cr:rectangle(x, y, w, h)
	cr:stroke()

	self:add_content_box(x, y, w, h)
end

function imgui:begin_window(cw, ch)
	local cr = self.cr
	push(self.window_stack, {
		cw = self.cw,
		ch = self.ch,
		matrix = self.cr:matrix(),
	})
	cr:translate(cx, cy)
	self.cw = cw
	self.ch = ch
end

function imgui:end_window()
	local cr = self.cr
	local t = pop(self.window_stack)
	self.cw = t.cw
	self.ch = t.ch
	self.cr:matrix(t.matrix)
end

function imgui:begin_clip()
	local cr = self.cr
	cr:save()
	cr:rectangle(0, 0, self.cw, self.ch)
	cr:clip()
end

function imgui:end_clip()
	cr:restore()
end

--layers ---------------------------------------------------------------------

function imgui:set_layer(id)

end

function imgui:begin_layer(id)

end

function imgui:end_layer()

end

--mouse & keyboard -----------------------------------------------------------

function imgui:mousepos()
	if not self.mousex then return end
	return self.cr:device_to_user(self.mousex, self.mousey)
end

function imgui:hotbox(x, y, w, h)
	local mx, my = self:mousepos()
	if not mx then return false end
	return
		box2d.hit(mx, my, x, y, w, h)
		and self.cr:in_clip(mx, my)
		--and self.layers:hit_layer(mx, my, self.current_layer)
end

function imgui:keypressed(keyname)
	return self:_backend_key_state(keyname)
end

--animation ------------------------------------------------------------------

local stopwatch = {}

function imgui:stopwatch(duration, formula)
	local t = glue.inherit({imgui = self, start = self.clock,
		duration = duration, formula = formula}, stopwatch)
	self.stopwatches[t] = true
	return t
end

function stopwatch:finished()
	return self.imgui.clock - self.start > self.duration
end

function stopwatch:progress()
	if self.formula then
		if type(self.formula) == 'string' then
			local easing = require'easing'
			formula = easing[formula]
		end
		return math.min(formula((self.imgui.clock - self.start), 0, 1, self.duration), 1)
	else
		return math.min((self.imgui.clock - self.start) / self.duration, 1)
	end
end

--imgui controller -----------------------------------------------------------

function imgui:new()

	--NOTE: this is shallow copy, so themes and default tables are shared
	--between all instances.
	local inst = glue.update({}, self)
	inst.new = false --prevent instantiating from the instance

	--statically inherit imgui extensions loaded at runtime
	local self = setmetatable(inst, {__index = function(t, k)
		local v = self[k]
		rawset(t, k, v)
		return v
	end})

	--one-shot init trigger: set to true only on the first frame
	self.init = true

	--mouse one-shot state, set when mouse state changed between frames
	self.clicked = false       --left mouse button clicked (one-shot)
	self.rightclick = false    --right mouse button clicked (one-shot)
	self.doubleclicked = false --left mouse button double-clicked (one-shot)
	self.tripleclicked = false --left mouse button triple-clicked (one-shot)
	self.wheel_delta = 0       --mouse wheel number of scroll pages (one-shot)

	--keyboard state: to be set on keyboard events
	self.key = nil
	self.char = nil
	self.shift = false
	self.ctrl = false
	self.alt = false

	--widget state
	self.active = nil   --has mouse focus
	self.focused = nil  --has keyboard focus
	self.ui = {}        --state to be used by the control.

	--animation state
	self.stopwatches = {} --{[stopwatch] = stopwatch_object}

	--event stream
	self.events = {}

	return self
end

function imgui:_backend_mousemove(x, y)
	self.mousex = x
	self.mousey = y
end

function imgui:_backend_mouseenter(x, y)

end

function imgui:_backend_mouseleave()

end

function imgui:_backend_event(...)
	local clock = self:_backend_clock()
	pushvar(self.events, clock, ...)
end

function imgui:_consume_event(clock, event, ...)
	if not clock then return end
	self.clock = clock
	self[event](self, ...)
	popvar(self.events)
end

function imgui:_render_pass()

	--reset the theme
	self.theme = self.default_theme

	self.cw, self.ch = self:_backend_client_size()

	self:_init_frame_layout()

	--reset the graphics context
	self.cr:reset_clip()
	self.cr:identity_matrix()

	--clear the background
	self:setcolor'window_bg'
	self.cr:paint()

	--remove any finished stopwatches
	for t in pairs(self.stopwatches) do
		if t:finished() then
			self.stopwatches[t] = nil
		end
	end

	--stuff to do only on first frame
	if self.init then
		imgui.mousex,
		imgui.mousey,
		imgui.lbutton,
		imgui.rbutton =
			self:_backend_mouse_state()
	end

	--render the app frame
	self:_backend_render_frame()

	--magnifier glass: so useful it's enabled by default
	if self.show_magnifier and self:keypressed'ctrl' and self.mousex then
		self.cr:identity_matrix()
		self:magnifier{
			id = 'mag',
			x = self.mousex - 200,
			y = self.mousey - 100,
			w = 400,
			h = 200,
			zoom_level = 4,
		}
	end

	--set/reset the window title
	self:_backend_set_title(self.title)
	self.title = nil

	--set/reset the mouse cursor
	self:_backend_set_cursor(self.cursor)
	self.cursor = nil

	--reset layout state
	self.cw = self._cw
	self.ch = self._ch

	--reset the one-shot mouse state vars
	self.lpressed = false
	self.rpressed = false
	self.clicked = false
	self.rightclick = false
	self.doubleclicked = false
	self.tripleclicked = false
	self.wheel_delta = 0

	--reset the one-shot keyboard state vars
	self.key = nil
	self.char = nil

	--reset the one-shot init trigger
	self.init = false

end

function imgui:_render_frame() --to be called on window's repaint event
	repeat
		self:_consume_event(topvar(self.events))
		repeat
			self._frame_valid = true
			self:_render_pass()
		until self._frame_valid
	until not top(self.events)
end

function imgui:invalidate()
	self._frame_valid = false
end

--label widget ---------------------------------------------------------------

function imgui:label_extents(s)
	local cr = self.cr
	local ext = cr:text_extents(s)
	return ext.width, ext.height, ext.y_bearing
end

function imgui:label(s)
	local cr = self.cr
	local w, h, yb = self:label_extents(s)
	local x, y, w, h = self:content_box(w, h)
	cr:move_to(x, -yb)
	cr:show_text(s)
	self:add_content_box(x, y, w, h)
	return x, y, w, h
end

--image widget ---------------------------------------------------------------

function imgui:image(src)

	--link image bits to a surface
	local img = src
	if src.format ~= 'bgra8'
		or src.bottom_up
		or bitmap.stride(src) ~=
			bitmap.aligned_stride(bitmap.min_stride(src.format, src.w))
	then
		img = bitmap.new(src.w, src.h, 'bgra8', false, true)
		bitmap.paint(src, img)
	end
	local surface = cairo.image_surface(img)

	local mt = self.cr:matrix()
	self.cr:translate(x, y)
	if t.scale then
		self.cr:scale(t.scale, t.scale)
	end
	self.cr:source(surface)
	self.cr:paint()
	self.cr:rgb(0,0,0)
	self.cr:matrix(mt)

	surface:free()
end

--external widgets -----------------------------------------------------------

glue.autoload(imgui, {
	--containers
	vscrollbar     = 'imgui_scrollbars',
	hscrollbar     = 'imgui_scrollbars',
	scrollbox      = 'imgui_scrollbars',
	vsplitter      = 'imgui_splitter',
	hsplitter      = 'imgui_splitter',
	toolbox        = 'imgui_toolbox',
	tablist        = 'imgui_tablist',
	--actionables
	button         = 'imgui_buttons',
	mbutton        = 'imgui_buttons',
	togglebutton   = 'imgui_buttons',
	slider         = 'imgui_slider',
	menu           = 'imgui_menu',
	dragpoint      = 'imgui_dragpoint',
	dragpoints     = 'imgui_dragpoint',
	hue_wheel      = 'imgui_hue_wheel',
	sat_lum_square = 'imgui_sat_lum_square',
	--text editing
	editbox        = 'imgui_editbox',
	combobox       = 'imgui_combobox',
	filebox        = 'imgui_filebox',
	screen         = 'imgui_screen',
	--tools
	magnifier      = 'imgui_magnifier',
	checkerboard   = 'imgui_checkerboard',
	--toys
	analog_clock   = 'imgui_analog_clock',
	--complex
	code_editor    = 'imgui_code_editor',
	grid           = 'imgui_grid',
	treeview       = 'imgui_treeview',
})

return imgui
