package controller

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type AetherController struct {
	BaseController

	inboundController *InboundController
	settingController *SettingController
}

func NewAetherController(g *gin.RouterGroup) *AetherController {
	a := &AetherController{}
	a.initRouter(g)
	return a
}

func (a *AetherController) initRouter(g *gin.RouterGroup) {
	
	ag := g.Group("/aether")
	ag.Use(a.checkLogin)

	ag.GET("/", a.index)
	ag.GET("/inbounds", a.inbounds)
	ag.GET("/clients", a.clients)
	ag.GET("/setting", a.setting)

	a.inboundController = NewInboundController(ag)
	a.settingController = NewSettingController(ag)

	
	xg := g.Group("/xui")
	xg.Use(a.checkLogin)
	xg.GET("/", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/") })
	xg.GET("/inbounds", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/inbounds") })
	xg.GET("/clients", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/clients") })
	xg.GET("/setting", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/setting") })
	NewInboundController(xg)
	NewSettingController(xg)
}

func (a *AetherController) index(c *gin.Context) {
	html(c, "index.html", "System Status", nil)
}

func (a *AetherController) inbounds(c *gin.Context) {
	html(c, "inbounds.html", "Inbounds", nil)
}

func (a *AetherController) clients(c *gin.Context) {
	html(c, "clients.html", "Clients & QR Links", nil)
}

func (a *AetherController) setting(c *gin.Context) {
	html(c, "setting.html", "Panel Settings", nil)
}
