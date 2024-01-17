#pragma once

#include <memory>
#include "renderer.h"

#include "window.h"

namespace core
{
	class application
	{
	public:
		std::shared_ptr<Window> window;
		std::shared_ptr<Renderer> renderer;

	public:
		application(int h, int w, const char* name);
		void run();

	private:
		int m_height;
		int m_width;
		const char* m_name;

	};
}