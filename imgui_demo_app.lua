
if not ... then require'imgui_demo'; return end

return function(self)
	local cr = self.cr

	cr:translate(0.5, 0.5)

	cr:font_face('Fixedsys')
	cr:font_size(12)
	cr:rgb(1, 1, 1)

	--[[
	self:begin_content_box'h'
		self:begin_content_box'v'
			self:box('15%', '10%', 50, 50)
			self:label'hello'
			self:box('25%', '10%')
		self:end_content_box()
		self:box('10%', '25%')
		self:box('10%', '15%')
	self:end_content_box()
	]]

	self.halign = 'r'
	self.flow = 'h'
	self:box'20%'
	self:box'300'
	self.flow = 'v'
	self:box(nil, '20%')
	self:box(nil, '300')
	self:label('hello')
	self.halign = 'c'
	self:label('hello again')
	self:label('and again')
	self.halign = 'l'
	self:label('and again')
	--self:spacer(nil, 100)
	self:button('Hi I\'m a button!')
	--self:box()

	--[[
	self.flow = 'h'
	self.halign = 'l'
	self.valign = 'c'
	self:box(300, 200)
	--self.halign = 'r'
	--self:box'200'
	self:box()
	]]
end
