package controller

import (
	"github.com/gin-gonic/gin"
	"net/http"
	"aether-vpn/logger"
	"aether-vpn/web/service"
	"aether-vpn/web/session"
)

type LoginForm struct {
	Username string `json:"username" form:"username"`
	Password string `json:"password" form:"password"`
}

type IndexController struct {
	BaseController

	userService service.UserService
}

func NewIndexController(g *gin.RouterGroup) *IndexController {
	a := &IndexController{}
	a.initRouter(g)
	return a
}

func (a *IndexController) initRouter(g *gin.RouterGroup) {
	g.GET("/", a.index)
	g.POST("/login", a.login)
	g.GET("/logout", a.logout)
}

func (a *IndexController) index(c *gin.Context) {
	if session.IsLogin(c) {
		c.Redirect(http.StatusTemporaryRedirect, "xui/")
		return
	}
	html(c, "login.html", "Aether VPN - Sign In", nil)
}

func (a *IndexController) login(c *gin.Context) {
	var form LoginForm
	err := c.ShouldBind(&form)
	if err != nil {
		pureJsonMsg(c, false, "Invalid data format")
		return
	}
	if form.Username == "" {
		pureJsonMsg(c, false, "Username cannot be empty")
		return
	}
	if form.Password == "" {
		pureJsonMsg(c, false, "Password cannot be empty")
		return
	}
	user := a.userService.CheckUser(form.Username, form.Password)
	if user == nil {
		logger.Infof("wrong username or password: \"%s\" \"%s\"", form.Username, form.Password)
		pureJsonMsg(c, false, "Invalid username or password")
		return
	}

	err = session.SetLoginUser(c, user)
	logger.Info("user", user.Id, "login success")
	jsonMsg(c, "Sign in", err)
}

func (a *IndexController) logout(c *gin.Context) {
	user := session.GetLoginUser(c)
	if user != nil {
		logger.Info("user", user.Id, "logout")
	}
	session.ClearSession(c)
	c.Redirect(http.StatusTemporaryRedirect, c.GetString("base_path"))
}
