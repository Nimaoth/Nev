import std/[macros, genasts]
import traits

type
  TextWidget = object
    text: string

  ButtonWidget = ref object
    text: string
    clicked: proc()

proc handleClick*(self: int, button: int): bool =
  echo "int.handleClick ", button

proc handleClick*(self: TextWidget, button: int): bool =
  echo "TextWidget.handleClick ", button

trait Widget:
  method draw*(self: Widget)
  method handleClick*(self: Widget, button: int): bool

trait Layout:
  method layout*(self: Layout, widgets: openArray[Widget])

##################################################################

implTrait(Widget, TextWidget):
  # handleClick(bool, TextWidget, int)
  handleClick
  # proc handleClick*(self: TextWidget, button: int): bool =
  #   echo "TextWidget.handleClick ", button

  proc draw*(self: TextWidget) =
    echo "TextWidget.draw: ", self.text

proc draw*(self: ButtonWidget) =
  echo "ButtonWidget.draw: ", self.text

implTrait(Widget, ButtonWidget):
  proc handleClick*(self: ButtonWidget, button: int): bool =
    echo "ButtonWidget.handleClick ", button
    self.clicked()
    return true

  draw(void, ButtonWidget)

proc foo(widget: Widget) =
  echo "foo"
  widget.draw()
  echo widget.handleClick(123)

proc bar[T: IWidget](widget: T) =
  echo "bar"
  widget.draw()
  echo widget.handleClick(456)

let text = TextWidget(text: "hi")
let button = ButtonWidget(text: "butt", clicked: proc() = echo "clicked")

text.asWidget.foo()
text.bar()

echo "o"

button.asWidget.foo()
button.bar()