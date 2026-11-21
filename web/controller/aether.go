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
	// Primary /aether group
	ag := g.Group("/aether")
	ag.Use(a.checkLogin)

	ag.GET("/", a.index)
	ag.GET("/inbounds", a.inbounds)
	ag.GET("/setting", a.setting)

	a.inboundController = NewInboundController(ag)
	a.settingController = NewSettingController(ag)

	// Legacy /xui redirect / fallback compatibility
	xg := g.Group("/xui")
	xg.Use(a.checkLogin)
	xg.GET("/", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/") })
	xg.GET("/inbounds", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/inbounds") })
	xg.GET("/setting", func(c *gin.Context) { c.Redirect(http.StatusMovedPermanently, "../aether/setting") })
	NewInboundController(xg)
	NewSettingController(xg)
}

func (a *AetherController) index(c *gin.Context) {
	html(c, "index.html", "Aether VPN - System Status", nil)
}

func (a *AetherController) inbounds(c *gin.Context) {
	html(c, "inbounds.html", "Aether VPN - Inbounds", nil)
}

func (a *AetherController) setting(c *gin.Context) {
	html(c, "setting.html", "Aether VPN - Panel Settings", nil)
}
